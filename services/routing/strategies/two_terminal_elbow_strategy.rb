module DuctExtension
  module Services
    module Routing
      module Strategies
        module TwoTerminalElbowStrategy
          def self.steps(context)
            start_point = context.start_point
            target_point = context.target_point
            source_vector = context.source_vector
            target_incoming_vector = context.target_incoming_vector
            dimensions = context.dimensions
            bend_radius = RouteMath.bend_radius_for(dimensions)

            best_steps = nil
            best_score = nil

            mid_direction_candidates(context).each do |middle_direction|
              middle_direction = Geometry::VectorMath.normalized(middle_direction)
              next unless middle_direction
              next if middle_direction.parallel?(source_vector)
              next if middle_direction.parallel?(target_incoming_vector)

              first_angle = source_vector.angle_between(middle_direction)
              second_angle = middle_direction.angle_between(target_incoming_vector)
              next unless RouteMath.valid_elbow_angle?(first_angle)
              next unless RouteMath.valid_elbow_angle?(second_angle)

              first_exit = RouteMath.elbow_exit_point(
                start_point,
                source_vector,
                middle_direction,
                bend_radius
              )
              next unless first_exit

              second_delta = RouteMath.elbow_exit_delta(
                entry_vector: middle_direction,
                exit_vector: target_incoming_vector,
                bend_radius: bend_radius
              )
              next unless second_delta

              second_start = target_point.offset(second_delta.reverse)
              bridge = first_exit.vector_to(second_start)
              next if bridge.length < RouteMath::MIN_ROUTE_LENGTH

              bridge_direction = bridge.clone
              bridge_direction.normalize!
              next if bridge_direction.dot(middle_direction) < 0.55

              score =
                bridge.length +
                ((1.0 - bridge_direction.dot(middle_direction)).abs * 16.0) +
                (first_angle * 1.5) +
                (second_angle * 1.5)

              candidate_steps = [
                Model::BuildStep.new(
                  :elbow,
                  dimensions.merge(
                    source_port: context.source_port,
                    start_point: start_point,
                    entry_vector: source_vector,
                    exit_vector: middle_direction,
                    bend_radius: bend_radius
                  )
                ),
                Model::BuildStep.new(
                  :pipe,
                  dimensions.merge(
                    deferred_start: true,
                    end_point: second_start
                  )
                ),
                Model::BuildStep.new(
                  :elbow,
                  dimensions.merge(
                    start_point: second_start,
                    entry_vector: middle_direction,
                    exit_vector: target_incoming_vector,
                    bend_radius: bend_radius
                  )
                )
              ]

              if best_steps.nil? || score < best_score
                best_steps = candidate_steps
                best_score = score
              end
            end

            best_steps
          end

          def self.mid_direction_candidates(context)
            candidates = []
            direct = context.start_point.vector_to(context.target_point)

            if direct.length > 0.0
              direct.normalize!
              candidates << direct
              candidates << RouteMath.weighted_sum(direct, 0.80, context.source_vector, 0.20)
              candidates << RouteMath.weighted_sum(direct, 0.80, context.target_incoming_vector, 0.20)
              candidates << RouteMath.weighted_sum(direct, 0.60, context.target_incoming_vector, 0.40)
            end

            candidates << RouteMath.vector_sum(context.source_vector, context.target_incoming_vector)
            candidates << context.target_incoming_vector
            candidates.concat(RouteMath.axis_candidates)
            RouteMath.unique_directions(candidates)
          end
          private_class_method :mid_direction_candidates
        end
      end
    end
  end
end
