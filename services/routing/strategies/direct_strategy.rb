module DuctExtension
  module Services
    module Routing
      module Strategies
        module DirectStrategy
          def self.steps(context)
            return nil unless RouteMath.direct_connection_possible?(context)

            [
              Model::BuildStep.new(
                :pipe,
                context.dimensions.merge(
                  source_port: context.source_port,
                  start_point: context.start_point,
                  end_point: context.target_point
                )
              )
            ]
          end
        end
      end
    end
  end
end
