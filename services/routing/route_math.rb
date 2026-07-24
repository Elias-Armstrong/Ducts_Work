module DuctExtension
  module Services
    module Routing
      module RouteMath
        MIN_ROUTE_LENGTH = 0.75
        DIRECTION_MATCH_DOT = 0.98
        TARGET_ALIGNMENT_DOT = 0.965
        DEFAULT_BEND_RADIUS_FACTOR = 1.5
        TWO_TERMINAL_MISS_TOLERANCE = 0.05

        def self.direct_connection_possible?(context)
          path = context.start_point.vector_to(context.target_point)
          return false if path.length <= 0.0

          path.normalize!
          context.source_vector.dot(path) >= DIRECTION_MATCH_DOT &&
            context.target_incoming_vector.dot(path) >= DIRECTION_MATCH_DOT
        end

        def self.axis_candidates
          base = [
            Geom::Vector3d.new(1, 0, 0),
            Geom::Vector3d.new(0, 1, 0),
            Geom::Vector3d.new(0, 0, 1)
          ]
          base.flat_map { |vector| [vector, vector.clone.reverse] }
        end

        def self.elbow_exit_delta(entry_vector:, exit_vector:, bend_radius:)
          origin = Geom::Point3d.new(0, 0, 0)
          exit_point = elbow_exit_point(origin, entry_vector, exit_vector, bend_radius)
          exit_point ? origin.vector_to(exit_point) : nil
        end

        def self.closest_points_between_lines(**args)
          Geometry::VectorMath.closest_points_between_lines(**args)
        end

        def self.bend_radius_for(dimensions)
          Model::DuctDimensions.coerce(dimensions).largest * DEFAULT_BEND_RADIUS_FACTOR
        end

        def self.valid_elbow_angle?(angle)
          angle > 0.01 && angle < Math::PI - 0.01
        end

        def self.elbow_exit_point(start_point, entry_vector, exit_vector, bend_radius)
          if defined?(Geometry::ElbowBuilder) && Geometry::ElbowBuilder.respond_to?(:exit_point)
            return Geometry::ElbowBuilder.exit_point(
              start_point,
              entry_vector,
              exit_vector,
              bend_radius
            )
          end

          entry = Geometry::VectorMath.normalized(entry_vector)
          exitv = Geometry::VectorMath.normalized(exit_vector)
          return nil unless entry && exitv

          angle = entry.angle_between(exitv)
          return nil unless valid_elbow_angle?(angle)

          normal = entry.cross(exitv)
          return nil if normal.length == 0
          normal.normalize!

          center_offset = normal.cross(entry)
          return nil if center_offset.length == 0
          center_offset.normalize!

          center = start_point.offset(center_offset, bend_radius)
          rotation = Geom::Transformation.rotation(center, normal, angle)
          start_point.transform(rotation)
        rescue
          nil
        end

        def self.vector_sum(vector_a, vector_b)
          Geometry::VectorMath.vector_sum(vector_a, vector_b)
        end

        def self.weighted_sum(vector_a, weight_a, vector_b, weight_b)
          Geometry::VectorMath.weighted_sum(vector_a, weight_a, vector_b, weight_b)
        end

        # Route candidates treat +v and -v as distinct oriented directions.
        def self.unique_directions(directions)
          Geometry::VectorMath.unique_directions(directions, tolerance: 0.001, ignore_sign: false)
        end
      end
    end
  end
end
