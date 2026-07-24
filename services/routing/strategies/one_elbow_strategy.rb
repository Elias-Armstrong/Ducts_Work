module DuctExtension
  module Services
    module Routing
      module Strategies
        module OneElbowStrategy
          def self.steps(context)
            bend_radius = RouteMath.bend_radius_for(context.dimensions)

            direct_target_steps(context, bend_radius) ||
              target_approach_steps(context, bend_radius)
          end

          def self.direct_target_steps(context, bend_radius)
            path = context.start_point.vector_to(context.target_point)
            return nil if path.length < RouteMath::MIN_ROUTE_LENGTH

            path_direction = path.clone
            path_direction.normalize!
            return nil if context.target_incoming_vector.dot(path_direction) < RouteMath::TARGET_ALIGNMENT_DOT

            source_angle = context.source_vector.angle_between(path_direction)
            return nil unless RouteMath.valid_elbow_angle?(source_angle)

            elbow_exit = RouteMath.elbow_exit_point(
              context.start_point,
              context.source_vector,
              path_direction,
              bend_radius
            )
            return nil unless elbow_exit

            remaining = elbow_exit.vector_to(context.target_point)
            return nil if remaining.length < RouteMath::MIN_ROUTE_LENGTH

            remaining_direction = remaining.clone
            remaining_direction.normalize!
            return nil if remaining_direction.dot(path_direction) < RouteMath::TARGET_ALIGNMENT_DOT

            [
              Model::BuildStep.new(
                :elbow,
                context.dimensions.merge(
                  source_port: context.source_port,
                  start_point: context.start_point,
                  entry_vector: context.source_vector,
                  exit_vector: path_direction,
                  bend_radius: bend_radius
                )
              ),
              Model::BuildStep.new(
                :pipe,
                context.dimensions.merge(
                  deferred_start: true,
                  end_point: context.target_point
                )
              )
            ]
          end
          private_class_method :direct_target_steps

          def self.target_approach_steps(context, bend_radius)
            final_direction = context.target_incoming_vector.clone
            final_direction.normalize!

            source_angle = context.source_vector.angle_between(final_direction)
            return nil unless RouteMath.valid_elbow_angle?(source_angle)

            elbow_exit = RouteMath.elbow_exit_point(
              context.start_point,
              context.source_vector,
              final_direction,
              bend_radius
            )
            return nil unless elbow_exit

            remaining = elbow_exit.vector_to(context.target_point)
            return nil if remaining.length < RouteMath::MIN_ROUTE_LENGTH

            remaining_direction = remaining.clone
            remaining_direction.normalize!
            return nil if remaining_direction.dot(final_direction) < RouteMath::TARGET_ALIGNMENT_DOT

            [
              Model::BuildStep.new(
                :elbow,
                context.dimensions.merge(
                  source_port: context.source_port,
                  start_point: context.start_point,
                  entry_vector: context.source_vector,
                  exit_vector: final_direction,
                  bend_radius: bend_radius
                )
              ),
              Model::BuildStep.new(
                :pipe,
                context.dimensions.merge(
                  deferred_start: true,
                  end_point: context.target_point
                )
              )
            ]
          end
          private_class_method :target_approach_steps
        end
      end
    end
  end
end
