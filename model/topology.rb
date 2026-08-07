# ===== Consolidated from: model/port.rb =====
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

# ===== Consolidated from: model/duct_piece.rb =====
module DuctExtension
  module Model
    class DuctPiece
      attr_accessor :type
      attr_accessor :group
      attr_accessor :ports

      def initialize(type:, group:, ports:)
        @type = type.to_sym
        @group = group
        @ports = ports || []

        @ports.each do |port|
          port.piece = self if port.respond_to?(:piece=)
        end
      end

      def valid?
        @group && @group.valid?
      end

      def round?
        shape == :round
      end

      def rectangular?
        shape == :rectangular
      end

      def shape
        first_port = @ports.find { |port| port.respond_to?(:shape) }
        first_port ? first_port.shape : :round
      end

      def diameter
        first_port = @ports.find { |port| port.respond_to?(:diameter) }
        first_port ? first_port.diameter : 8.0
      end

      def width
        first_port = @ports.find { |port| port.respond_to?(:width) }
        first_port ? first_port.width : diameter
      end

      def height
        first_port = @ports.find { |port| port.respond_to?(:height) }
        first_port ? first_port.height : diameter
      end
    end
  end
end

# ===== Consolidated from: model/connection.rb =====
module DuctExtension
  module Model
    class Connection
      attr_reader :port_a
      attr_reader :port_b

      def initialize(port_a, port_b)
        @port_a = port_a
        @port_b = port_b
      end

      def includes?(port)
        @port_a == port || @port_b == port
      end

      def includes_any?(ports)
        Array(ports).any? { |port| includes?(port) }
      end

      def other(port)
        return @port_b if @port_a == port
        return @port_a if @port_b == port

        nil
      end

      def valid?
        @port_a &&
          @port_b &&
          @port_a.piece &&
          @port_b.piece &&
          @port_a.piece.group &&
          @port_b.piece.group &&
          @port_a.piece.group.valid? &&
          @port_b.piece.group.valid?
      end
    end
  end
end
