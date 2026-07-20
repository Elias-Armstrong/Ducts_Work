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

      # Rectangular frame orientation.
      # Round ducts ignore these.
      attr_accessor :width_axis
      attr_accessor :height_axis

      DEFAULT_DIAMETER = 8.0
      DEFAULT_WIDTH = 12.0
      DEFAULT_HEIGHT = 8.0

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
        @vector = normalized_vector(vector) || Geom::Vector3d.new(1, 0, 0)

        @shape = normalize_shape(shape)

        @diameter = positive_number(diameter, DEFAULT_DIAMETER)

        if @shape == :rectangular
          @width = positive_number(width, @diameter)
          @height = positive_number(height, @diameter)
        else
          @width = @diameter
          @height = @diameter
        end

        @piece = piece

        @width_axis = normalized_vector(width_axis)
        @height_axis = normalized_vector(height_axis)
      end

      def outward_vector
        @vector
      end

      def outward_vector=(value)
        @vector = normalized_vector(value) || @vector
      end

      def round?
        @shape == :round
      end

      def rectangular?
        @shape == :rectangular
      end

      def same_location?(other, tolerance = 0.05)
        return false unless other
        return false unless other.respond_to?(:point)

        @point.distance(other.point) <= tolerance
      end

      def dimensions
        {
          shape: @shape,
          diameter: @diameter,
          width: @width,
          height: @height
        }
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
        params ||= {}

        fallback_shape =
          if fallback_port && fallback_port.respond_to?(:shape)
            fallback_port.shape
          else
            :round
          end

        shape = normalize_shape_value(params[:shape] || params["shape"] || fallback_shape)

        fallback_diameter =
          if fallback_port && fallback_port.respond_to?(:diameter)
            fallback_port.diameter
          else
            DEFAULT_DIAMETER
          end

        diameter = positive_number_value(
          params[:diameter] || params["diameter"],
          fallback_diameter
        )

        if shape == :rectangular
          fallback_width =
            if fallback_port && fallback_port.respond_to?(:width)
              fallback_port.width
            else
              DEFAULT_WIDTH
            end

          fallback_height =
            if fallback_port && fallback_port.respond_to?(:height)
              fallback_port.height
            else
              DEFAULT_HEIGHT
            end

          width = positive_number_value(params[:width] || params["width"], fallback_width)
          height = positive_number_value(params[:height] || params["height"], fallback_height)

          {
            shape: :rectangular,
            diameter: [width, height].max,
            width: width,
            height: height
          }
        else
          {
            shape: :round,
            diameter: diameter,
            width: diameter,
            height: diameter
          }
        end
      end

      def self.normalize_shape_value(value)
        text = value.to_s.downcase.strip

        case text
        when "rectangular", "rectangle", "rect", "square"
          :rectangular
        else
          :round
        end
      end

      def self.positive_number_value(value, fallback)
        number = value.to_f
        number > 0 ? number : fallback.to_f
      rescue
        fallback.to_f
      end

      private

      def normalize_shape(value)
        self.class.normalize_shape_value(value)
      end

      def positive_number(value, fallback)
        self.class.positive_number_value(value, fallback)
      end

      def to_point3d(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          Geom::Point3d.new(0, 0, 0)
        end
      end

      def normalized_vector(value)
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
        return nil if vector.length == 0

        vector.normalize!
        vector
      rescue
        nil
      end
    end
  end
end
