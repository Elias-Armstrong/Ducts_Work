# ===== Consolidated from: services/routing/strategies/direct_strategy.rb =====
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

# ===== Consolidated from: services/routing/strategies/two_terminal_elbow_strategy.rb =====
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

            best_steps = nil
            best_score = nil

            mid_direction_candidates(context).each do |middle_direction|
              middle_direction = Geometry::VectorMath.normalized(middle_direction)
              next unless middle_direction
              next if middle_direction.parallel?(source_vector)
              next if middle_direction.parallel?(target_incoming_vector)

              first_angle = source_vector.angle_between(middle_direction)
              second_angle = middle_direction.angle_between(target_incoming_vector)
              next unless RouteMath.valid_elbow_angle?(first_angle, dimensions)
              next unless RouteMath.valid_elbow_angle?(second_angle, dimensions)

              first_bend_radius = RouteMath.bend_radius_for(dimensions, angle: first_angle)
              second_bend_radius = RouteMath.bend_radius_for(dimensions, angle: second_angle)

              first_exit = RouteMath.elbow_exit_point(
                start_point,
                source_vector,
                middle_direction,
                first_bend_radius
              )
              next unless first_exit

              second_delta = RouteMath.elbow_exit_delta(
                entry_vector: middle_direction,
                exit_vector: target_incoming_vector,
                bend_radius: second_bend_radius
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
                    bend_radius: first_bend_radius
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
                    bend_radius: second_bend_radius
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

# ===== Consolidated from: services/routing/strategies/one_elbow_strategy.rb =====
module DuctExtension
  module Services
    module Routing
      module Strategies
        module OneElbowStrategy
          def self.steps(context)
            direct_target_steps(context) || target_approach_steps(context)
          end

          def self.direct_target_steps(context)
            path = context.start_point.vector_to(context.target_point)
            return nil if path.length < RouteMath::MIN_ROUTE_LENGTH

            path_direction = path.clone
            path_direction.normalize!
            return nil if context.target_incoming_vector.dot(path_direction) < RouteMath::TARGET_ALIGNMENT_DOT

            source_angle = context.source_vector.angle_between(path_direction)
            return nil unless RouteMath.valid_elbow_angle?(source_angle, context.dimensions)
            bend_radius = RouteMath.bend_radius_for(context.dimensions, angle: source_angle)

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

          def self.target_approach_steps(context)
            final_direction = context.target_incoming_vector.clone
            final_direction.normalize!

            source_angle = context.source_vector.angle_between(final_direction)
            return nil unless RouteMath.valid_elbow_angle?(source_angle, context.dimensions)
            bend_radius = RouteMath.bend_radius_for(context.dimensions, angle: source_angle)

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

# ===== Consolidated from: services/routing/strategies/dogleg_strategy.rb =====
module DuctExtension
  module Services
    module Routing
      module Strategies
        module DoglegStrategy
          def self.steps(context)
            best_steps = nil
            best_score = nil

            RouteMath.axis_candidates.each do |dogleg_direction|
              dogleg_direction = Geometry::VectorMath.normalized(dogleg_direction)
              next unless dogleg_direction
              next if dogleg_direction.parallel?(context.source_vector)
              next if dogleg_direction.parallel?(context.target_incoming_vector)

              first_angle = context.source_vector.angle_between(dogleg_direction)
              second_angle = dogleg_direction.angle_between(context.target_incoming_vector)
              next unless RouteMath.valid_elbow_angle?(first_angle, context.dimensions)
              next unless RouteMath.valid_elbow_angle?(second_angle, context.dimensions)
              first_bend_radius = RouteMath.bend_radius_for(context.dimensions, angle: first_angle)
              second_bend_radius = RouteMath.bend_radius_for(context.dimensions, angle: second_angle)

              first_exit = RouteMath.elbow_exit_point(
                context.start_point,
                context.source_vector,
                dogleg_direction,
                first_bend_radius
              )
              next unless first_exit

              second_delta = RouteMath.elbow_exit_delta(
                entry_vector: dogleg_direction,
                exit_vector: context.target_incoming_vector,
                bend_radius: second_bend_radius
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
                    bend_radius: first_bend_radius
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
                    bend_radius: second_bend_radius
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

# ===== Consolidated from: services/routing/strategy_pipeline.rb =====
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
