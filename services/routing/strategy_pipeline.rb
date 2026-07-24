module DuctExtension
  module Services
    module Routing
      module StrategyPipeline
        STRATEGIES = [
          Strategies::TwoTerminalElbowStrategy,
          Strategies::OneElbowStrategy,
          Strategies::DoglegStrategy
        ].freeze

        def self.steps(context)
          return nil unless context && context.valid?

          direct = Strategies::DirectStrategy.steps(context)
          return direct if direct
          return nil if context.straight_only?

          STRATEGIES.each do |strategy|
            result = strategy.steps(context)
            return result if result && !result.empty?
          end

          nil
        rescue => error
          puts "Routing::StrategyPipeline.steps failed: #{error.message}"
          puts error.backtrace.join("\n")
          nil
        end
      end
    end
  end
end
