require_relative 'spec_helper'
require_relative 'support/queue_helpers'

describe Consumer do
  include QueueHelpers

  describe "#run" do
    it "increments the counters on the statsd client" do
      statsd_client = StatsdClientMock.new
      queue = create_stubbed_queue

      expect(queue).to receive(:subscribe).and_yield(
        double(:delivery_info, channel: double(:channel, reject: double), delivery_tag: double),
        double(:headers, content_type: 'application/json'),
        "message_payload"
      )

      Consumer.new(queue_name: "some-queue", exchange_name: "my-exchange", processor: double, statsd_client: statsd_client).run

      expect(statsd_client.incremented_keys).to eql(['some-queue.started', 'some-queue.discarded'])
    end

    it "increments the uncaught_exception counter for uncaught exceptions" do
      statsd_client = StatsdClientMock.new
      queue = create_stubbed_queue

      expect(queue).to receive(:subscribe).and_yield(
        double(:delivery_info, channel: double(:channel, reject: double), delivery_tag: double),
        double(:headers, content_type: 'application/json'),
        {}.to_json
      )

      processor = double
      expect(processor).to receive(:process).and_raise("An exception")

      expect do
        Consumer.new(queue_name: "some-queue", exchange_name: "my-exchange", processor: processor, statsd_client: statsd_client).run
      end.to raise_error(SystemExit)

      expect(statsd_client.incremented_keys).to eql(['some-queue.started', 'some-queue.uncaught_exception'])
    end
  end

  class StatsdClientMock
    attr_reader :incremented_keys
    def initialize
      @incremented_keys = []
    end

    def increment(key)
      @incremented_keys << key
    end
  end
end
