module DuctExtension
  module Geometry
    module RectangularFrame
      EPSILON = 0.000001

      WORLD_X = Geom::Vector3d.new(1, 0, 0)
      WORLD_Y = Geom::Vector3d.new(0, 1, 0)
      WORLD_Z = Geom::Vector3d.new(0, 0, 1)

      HORIZONTAL_AXIS_MAX_Z_DOT = 0.20
      MIN_RELEVEL_UP_PROJECTION = 0.72

      # Basic basis builder.
      #
      # Rule:
      # - If a preferred rectangular frame is supplied, preserve it.
      # - Otherwise choose a safe fallback basis.
      def self.normalized(vector)
        VectorMath.normalized(vector, epsilon: EPSILON)
      end

      def self.point3d(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          nil
        end
      rescue
        nil
      end

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis, epsilon: EPSILON)
      end

      def self.fallback_perpendicular_axis(axis)
        VectorMath.fallback_perpendicular_axis(
          axis,
          epsilon: EPSILON,
          candidates: [WORLD_Z, WORLD_Y, WORLD_X]
        )
      end

      def self.best_reference_axis(axis)
        axis = normalized(axis)
        return WORLD_Z unless axis

        candidates = [WORLD_Z, WORLD_Y, WORLD_X]
        candidates.min_by { |candidate| candidate.dot(axis).abs }
      end
    end
  end
end
require_relative 'rectangular_frame/basis'
require_relative 'rectangular_frame/transport'
