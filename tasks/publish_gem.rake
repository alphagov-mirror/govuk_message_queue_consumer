require "gem_publisher"

desc "Publish gem to RubyGems.org"
task :publish_gem do |t|
  gem = GemPublisher.publish_if_updated("message-queue-consumer.gemspec", :rubygems)
  puts "Published #{gem}" if gem
end
