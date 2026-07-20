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
