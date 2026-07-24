module DuctExtension
  module Services
    module Routing
      module Strategies
        module DoglegStrategy
          def self.steps(context)
            bend_radius = RouteMath.bend_radius_for(context.dimensions)
            best_steps = nil
            best_score = nil

            RouteMath.axis_candidates.each do |dogleg_direction|
              dogleg_direction = Geometry::VectorMath.normalized(dogleg_direction)
              next unless dogleg_direction
              next if dogleg_direction.parallel?(context.source_vector)
              next if dogleg_direction.parallel?(context.target_incoming_vector)

              first_exit = RouteMath.elbow_exit_point(
                context.start_point,
                context.source_vector,
                dogleg_direction,
                bend_radius
              )
              next unless first_exit

              second_delta = RouteMath.elbow_exit_delta(
                entry_vector: dogleg_direction,
                exit_vector: context.target_incoming_vector,
                bend_radius: bend_radius
              )
              next unless second_delta

              target_line_point = context.target_point.offset(second_delta.reverse)
              closest = RouteMath.closest_points_between_lines(
                point_a: first_exit,
                dir_a: dogleg_direction,
                point_b: target_line_point,
                dir_b: context.target_incoming_vector.clone.reverse
              )
              next unless closest

              second_start = closest[:point_a]
              target_side_point = closest[:point_b]
              miss = second_start.distance(target_side_point)
              next if miss > RouteMath::TWO_TERMINAL_MISS_TOLERANCE

              first_straight_length = first_exit.distance(second_start)
              next if first_straight_length < RouteMath::MIN_ROUTE_LENGTH

              second_exit = second_start.offset(second_delta)
              final_length = second_exit.distance(context.target_point)
              next if final_length < RouteMath::MIN_ROUTE_LENGTH

              final_vector = second_exit.vector_to(context.target_point)
              final_vector.normalize!
              next if final_vector.dot(context.target_incoming_vector) < RouteMath::TARGET_ALIGNMENT_DOT

              score = first_straight_length + final_length + (miss * 8.0)
              candidate_steps = [
                Model::BuildStep.new(
                  :elbow,
                  context.dimensions.merge(
                    source_port: context.source_port,
                    start_point: context.start_point,
                    entry_vector: context.source_vector,
                    exit_vector: dogleg_direction,
                    bend_radius: bend_radius
                  )
                ),
                Model::BuildStep.new(
                  :pipe,
                  context.dimensions.merge(
                    deferred_start: true,
                    end_point: second_start
                  )
                ),
                Model::BuildStep.new(
                  :elbow,
                  context.dimensions.merge(
                    start_point: second_start,
                    entry_vector: dogleg_direction,
                    exit_vector: context.target_incoming_vector,
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

              if best_steps.nil? || score < best_score
                best_steps = candidate_steps
                best_score = score
              end
            end

            best_steps
          end
        end
      end
    end
  end
end
