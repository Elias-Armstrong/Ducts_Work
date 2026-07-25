module DuctExtension
  module Model
    class Port
      attr_accessor :point
      attr_accessor :vector
      attr_accessor :diameter
      attr_accessor :shape
      attr_accessor :width
      attr_accessor :height
      attr_accessor :piece

      # Rectangular frame orientation. Round ducts ignore these.
      attr_accessor :width_axis
      attr_accessor :height_axis

      DEFAULT_DIAMETER = DuctDimensions::DEFAULT_DIAMETER
      DEFAULT_WIDTH = DuctDimensions::DEFAULT_WIDTH
      DEFAULT_HEIGHT = DuctDimensions::DEFAULT_HEIGHT

      def initialize(
        point:,
        vector:,
        diameter: DEFAULT_DIAMETER,
        shape: :round,
        width: nil,
        height: nil,
        piece: nil,
        width_axis: nil,
        height_axis: nil
      )
        @point = to_point3d(point)
        @vector = Geometry::VectorMath.normalized(vector) || Geom::Vector3d.new(1, 0, 0)
        self.dimensions = DuctDimensions.new(
          shape: shape,
          diameter: diameter,
          width: width,
          height: height
        )
        @piece = piece
        @width_axis = Geometry::VectorMath.normalized(width_axis)
        @height_axis = Geometry::VectorMath.normalized(height_axis)
      end

      def dimensions
        DuctDimensions.new(
          shape: @shape,
          diameter: @diameter,
          width: @width,
          height: @height
        )
      end

      def dimensions=(value)
        normalized = DuctDimensions.coerce(value, fallback: dimensions_if_available)
        @shape = normalized.shape
        @diameter = normalized.diameter
        @width = normalized.width
        @height = normalized.height
        normalized
      end

      def outward_vector
        @vector
      end

      def outward_vector=(value)
        @vector = Geometry::VectorMath.normalized(value) || @vector
      end

      def round?
        @shape == :round
      end

      def rectangular?
        @shape == :rectangular
      end

      def same_location?(other, tolerance = 0.05)
        return false unless other && other.respond_to?(:point)

        @point.distance(other.point) <= tolerance
      end

      def to_h
        {
          "point" => @point.to_a,
          "vector" => @vector.to_a,
          "diameter" => @diameter,
          "shape" => @shape.to_s,
          "width" => @width,
          "height" => @height,
          "width_axis" => @width_axis ? @width_axis.to_a : nil,
          "height_axis" => @height_axis ? @height_axis.to_a : nil
        }
      end

      def self.from_h(data)
        return nil unless data

        new(
          point: data["point"] || data[:point],
          vector: data["vector"] || data[:vector],
          diameter: data["diameter"] || data[:diameter],
          shape: data["shape"] || data[:shape],
          width: data["width"] || data[:width],
          height: data["height"] || data[:height],
          width_axis: data["width_axis"] || data[:width_axis],
          height_axis: data["height_axis"] || data[:height_axis]
        )
      end

      def self.dimensions_from_params(params = {}, fallback_port = nil)
        fallback =
          if fallback_port && fallback_port.respond_to?(:dimensions)
            fallback_port.dimensions
          else
            nil
          end

        DuctDimensions.coerce(params || {}, fallback: fallback)
      end

      private

      def dimensions_if_available
        return nil unless defined?(@shape) && @shape

        {
          shape: @shape,
          diameter: @diameter,
          width: @width,
          height: @height
        }
      end

      def to_point3d(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          Geom::Point3d.new(0, 0, 0)
        end
      rescue
        Geom::Point3d.new(0, 0, 0)
      end
    end
  end
end
