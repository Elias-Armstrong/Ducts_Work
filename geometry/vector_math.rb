module DuctExtension
  module Geometry
    module VectorMath
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
      # the result. This is the shared implementation used throughout routing,
      # fitting insertion, and fitting geometry.
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
      # perpendicular plane. This preserves the fallback strategy previously
      # duplicated by several services.
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
    end
  end
end
