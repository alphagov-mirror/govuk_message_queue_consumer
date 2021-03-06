module GovukMessageQueueConsumer
  class Consumer
    HANDLE_BATCHES = false
    # Only fetch one message at a time on the channel.
    #
    # By default, queues will grab messages eagerly, which reduces latency.
    # However, that also means that if multiple workers are running one worker
    # can starve another of work.  We're not expecting a high throughput on this
    # queue, and a small bit of latency isn't a problem, so we fetch one at a
    # time to share the work evenly.
    NUMBER_OF_MESSAGES_TO_PREFETCH = 1

    # Create a new consumer
    #
    # @param queue_name [String] Your queue name. This is specific to your application,
    #                            and should already exist and have a binding via puppet
    # @param processor [Object] An object that responds to `process`
    # @param rabbitmq_connection [Object] A Bunny connection object derived from `Bunny.new`
    # @param statsd_client [Statsd] An instance of the Statsd class
    # @param logger [Object] A Logger object for emitting errors (to stderr by default)
    def initialize(queue_name:, processor:, rabbitmq_connection: Consumer.default_connection_from_env, statsd_client: NullStatsd.new, logger: Logger.new(STDERR))
      @queue_name = queue_name
      @processor = processor
      @rabbitmq_connection = rabbitmq_connection
      @statsd_client = statsd_client
      @logger = logger
    end

    def run(subscribe_opts: {})
      @rabbitmq_connection.start

      subscribe_opts = { block: true, manual_ack: true}.merge(subscribe_opts)
      queue.subscribe(subscribe_opts) do |delivery_info, headers, payload|
        begin
          message = Message.new(payload, headers, delivery_info)
          @statsd_client.increment("#{@queue_name}.started")
          message_consumer.process(message)
          @statsd_client.increment("#{@queue_name}.#{message.status}")
        rescue SignalException => e
          @logger.error "SignalException in processor: \n\n #{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}"
          exit(1) # Ensure rabbitmq requeues outstanding messages
        rescue Exception => e
          @statsd_client.increment("#{@queue_name}.uncaught_exception")
          GovukError.notify(e) if defined?(GovukError)
          @logger.error "Uncaught exception in processor: \n\n #{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}"
          exit(1) # Ensure rabbitmq requeues outstanding messages
        end
      end
    end

  private

    class NullStatsd
      def increment(_key)
      end

      def count(_key, _volume)
      end
    end

    def message_consumer
      @message_consumer ||= MessageConsumer.new(
        processors: [
          HeartbeatProcessor.new,
          JSONProcessor.new,
          @processor,
        ],
        handle_batches: self.class::HANDLE_BATCHES,
      )
    end

    def queue
      @queue ||= begin
        channel.prefetch(self.class::NUMBER_OF_MESSAGES_TO_PREFETCH)
        channel.queue(@queue_name, no_declare: true)
      end
    end

    def channel
      @channel ||= @rabbitmq_connection.create_channel
    end

    def self.default_connection_from_env
      Bunny.new(GovukMessageQueueConsumer::RabbitMQConfig.from_environment(ENV))
    end
  end
end
