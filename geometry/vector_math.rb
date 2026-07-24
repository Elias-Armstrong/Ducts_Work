module DuctExtension
  module Geometry
    module VectorMath
      EPSILON = 0.000001

      # Normalize a SketchUp vector (or any three-value object) without
      # modifying the caller's object. Returns nil for invalid/zero vectors.
      def self.normalized(value, epsilon: 0.0)
        return nil unless value

        vector =
          if value.is_a?(Geom::Vector3d)
            value.clone
          elsif value.respond_to?(:to_a)
            array = value.to_a
            Geom::Vector3d.new(array[0].to_f, array[1].to_f, array[2].to_f)
          else
            nil
          end

        return nil unless vector
        return nil if vector.length <= epsilon.to_f

        vector.normalize!
        vector
      rescue
        nil
      end

      # Project +vector+ onto the plane perpendicular to +axis+ and normalize
      # the result.
      def self.perpendicularized(vector, axis, epsilon: 0.0)
        side = normalized(vector, epsilon: epsilon)
        main = normalized(axis, epsilon: epsilon)
        return nil unless side && main

        amount = side.dot(main)
        result = Geom::Vector3d.new(
          side.x - main.x * amount,
          side.y - main.y * amount,
          side.z - main.z * amount
        )

        return nil if result.length <= epsilon.to_f

        result.normalize!
        result
      rescue
        nil
      end

      # Pick the world axis least parallel to +axis+, then project it into the
      # perpendicular plane.
      def self.fallback_perpendicular_axis(axis, epsilon: 0.0, candidates: nil)
        main = normalized(axis, epsilon: epsilon)
        return nil unless main

        candidates ||= [
          Geom::Vector3d.new(1, 0, 0),
          Geom::Vector3d.new(0, 1, 0),
          Geom::Vector3d.new(0, 0, 1)
        ]

        best = candidates.min_by { |candidate| candidate.dot(main).abs }
        perpendicularized(best, main, epsilon: epsilon)
      rescue
        nil
      end

      def self.vector_sum(vector_a, vector_b, epsilon: EPSILON)
        weighted_sum(vector_a, 1.0, vector_b, 1.0, epsilon: epsilon)
      end

      def self.weighted_sum(vector_a, weight_a, vector_b, weight_b, epsilon: EPSILON)
        a = normalized(vector_a, epsilon: epsilon)
        b = normalized(vector_b, epsilon: epsilon)
        return nil unless a && b

        result = Geom::Vector3d.new(
          (a.x * weight_a.to_f) + (b.x * weight_b.to_f),
          (a.y * weight_a.to_f) + (b.y * weight_b.to_f),
          (a.z * weight_a.to_f) + (b.z * weight_b.to_f)
        )

        return nil if result.length <= epsilon.to_f

        result.normalize!
        result
      rescue
        nil
      end

      # De-duplicate directions. By default opposite directions are distinct;
      # pass ignore_sign: true when an axis rather than an oriented vector is
      # being collected.
      def self.unique_directions(vectors, tolerance: 0.001, ignore_sign: false)
        unique = []

        Array(vectors).compact.each do |vector|
          candidate = normalized(vector)
          next unless candidate

          duplicate = unique.any? do |existing|
            dot = existing.dot(candidate)
            dot = dot.abs if ignore_sign
            dot >= (1.0 - tolerance.to_f)
          end

          unique << candidate unless duplicate
        end

        unique
      rescue
        []
      end

      # Return closest points on two infinite 3D lines. This is shared by tee
      # placement and route planning so the line math cannot drift between the
      # two systems.
      def self.closest_points_between_lines(point_a:, dir_a:, point_b:, dir_b:, epsilon: EPSILON)
        p1 = point_a
        d1 = normalized(dir_a, epsilon: epsilon)
        p2 = point_b
        d2 = normalized(dir_b, epsilon: epsilon)
        return nil unless p1 && p2 && d1 && d2

        r = p1.vector_to(p2)
        a = d1.dot(d1)
        e = d2.dot(d2)
        b = d1.dot(d2)
        c = d1.dot(r)
        f = d2.dot(r)
        denominator = a * e - b * b

        if denominator.abs < epsilon.to_f
          s = c / a
          t = 0.0
        else
          s = (b * f - c * e) / denominator
          t = (a * f - b * c) / denominator
        end

        {
          point_a: p1.offset(d1, s),
          point_b: p2.offset(d2, t),
          s: s,
          t: t
        }
      rescue
        nil
      end
    end
  end
end
