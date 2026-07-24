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
