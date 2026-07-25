module DuctExtension
  module Model
    # Immutable, normalized duct-size value object used across routing,
    # fitting construction, resizing, and metadata. It intentionally supports
    # Hash-like access/merge so existing callers can migrate without changing
    # their behavior all at once.
    class DuctDimensions
      DEFAULT_DIAMETER = 8.0
      DEFAULT_WIDTH = 12.0
      DEFAULT_HEIGHT = 8.0

      attr_reader :shape, :diameter, :width, :height

      def initialize(shape: :round, diameter: nil, width: nil, height: nil)
        @shape = self.class.normalize_shape(shape)

        if rectangular?
          fallback_width = self.class.positive_number(diameter, DEFAULT_WIDTH)
          @width = self.class.positive_number(width, fallback_width)
          @height = self.class.positive_number(height, self.class.positive_number(diameter, DEFAULT_HEIGHT))
          @diameter = [@width, @height].max
        else
          @diameter = self.class.positive_number(diameter, DEFAULT_DIAMETER)
          @width = @diameter
          @height = @diameter
        end

        freeze
      end

      def self.round(diameter: DEFAULT_DIAMETER)
        new(shape: :round, diameter: diameter)
      end

      def self.rectangular(width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT)
        new(shape: :rectangular, width: width, height: height)
      end

      def self.coerce(value = nil, fallback: nil, default_shape: :round)
        return value if value.is_a?(self)

        fallback_dimensions =
          if fallback.is_a?(self)
            fallback
          elsif fallback && fallback.respond_to?(:dimensions)
            coerce(fallback.dimensions, default_shape: default_shape)
          elsif fallback
            coerce(fallback, default_shape: default_shape)
          end

        source = value || {}
        shape_value = fetch_value(source, :shape)
        shape = normalize_shape(shape_value || (fallback_dimensions && fallback_dimensions.shape) || default_shape)

        if shape == :rectangular
          fallback_width = fallback_dimensions ? fallback_dimensions.width : DEFAULT_WIDTH
          fallback_height = fallback_dimensions ? fallback_dimensions.height : DEFAULT_HEIGHT

          width = positive_number(fetch_value(source, :width), fallback_width)
          height = positive_number(fetch_value(source, :height), fallback_height)

          new(shape: :rectangular, width: width, height: height)
        else
          fallback_diameter = fallback_dimensions ? fallback_dimensions.diameter : DEFAULT_DIAMETER
          diameter = positive_number(fetch_value(source, :diameter), fallback_diameter)
          new(shape: :round, diameter: diameter)
        end
      rescue
        fallback_dimensions || new(shape: default_shape)
      end

      def self.normalize_shape(value, default: :round)
        case value.to_s.downcase.strip
        when "rectangular", "rectangle", "rect", "square"
          :rectangular
        when "round", "circle", "circular"
          :round
        else
          default
        end
      rescue
        default
      end

      def self.positive_number(value, fallback = nil)
        number = value.to_f
        return number if number > 0.0

        fallback.nil? ? nil : fallback.to_f
      rescue
        fallback.nil? ? nil : fallback.to_f
      end

      def self.max_dimensions(first, second)
        first = coerce(first)
        second = coerce(second)

        if first.rectangular? || second.rectangular?
          rectangular(width: [first.width, second.width].max, height: [first.height, second.height].max)
        else
          round(diameter: [first.diameter, second.diameter].max)
        end
      end

      def self.fetch_value(source, key)
        if source.respond_to?(:[])
          value = source[key]
          value = source[key.to_s] if value.nil?
          return value unless value.nil?
        end

        source.public_send(key) if source.respond_to?(key)
      rescue
        nil
      end

      def round?
        @shape == :round
      end

      def rectangular?
        @shape == :rectangular
      end

      def largest
        [@diameter, @width, @height].max
      end

      def same_size?(other, tolerance: 0.001)
        other = self.class.coerce(other, fallback: self)
        return false unless @shape == other.shape

        if rectangular?
          (@width - other.width).abs <= tolerance.to_f &&
            (@height - other.height).abs <= tolerance.to_f
        else
          (@diameter - other.diameter).abs <= tolerance.to_f
        end
      rescue
        false
      end

      def [](key)
        case key.to_s
        when "shape" then @shape
        when "diameter" then @diameter
        when "width" then @width
        when "height" then @height
        end
      end

      def fetch(key, *args)
        value = self[key]
        return value unless value.nil?
        return args.first unless args.empty?

        raise KeyError, "key not found: #{key.inspect}"
      end

      def key?(key)
        %w[shape diameter width height].include?(key.to_s)
      end

      def to_h
        {
          shape: @shape,
          diameter: @diameter,
          width: @width,
          height: @height
        }
      end
      alias to_hash to_h

      def merge(other = nil, **kwargs)
        values = to_h
        values.merge!(other.to_h) if other.respond_to?(:to_h)
        values.merge!(kwargs) unless kwargs.empty?
        values
      end

      def with(**changes)
        self.class.coerce(to_h.merge(changes), fallback: self)
      end

      def ==(other)
        return false if other.nil?

        other = self.class.coerce(other)
        to_h == other.to_h
      rescue
        false
      end

      def inspect
        "#<#{self.class.name} shape=#{@shape.inspect} diameter=#{@diameter} width=#{@width} height=#{@height}>"
      end
    end
  end
end
