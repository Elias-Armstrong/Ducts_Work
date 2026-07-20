module DuctExtension
  module Model
    class Network
      SNAP_DISTANCE = 6.0
      CONNECTION_DISTANCE = 0.05

      attr_reader :pieces
      attr_reader :ports
      attr_reader :connections

      def initialize
        @pieces = []
        @ports = []
        @connections = []
        @spatial_index = SpatialPortIndex.new
      end

      def clear
        @pieces.clear
        @ports.clear
        @connections.clear
        @spatial_index.clear
      end

      def add_piece(piece)
        return unless piece
        return if @pieces.include?(piece)

        @pieces << piece

        Array(piece.ports).each do |port|
          add_port(port)
          port.piece = piece if port.respond_to?(:piece=)
        end
      end

      def remove_piece(piece)
        return unless piece

        @pieces.delete(piece)

        Array(piece.ports).each do |port|
          remove_port(port)
        end

        @connections.delete_if do |connection|
          connection.includes_any?(Array(piece.ports))
        rescue
          Array(piece.ports).any? { |port| connection.includes?(port) }
        end

        rebuild_index!
      end

      def add_port(port)
        return unless port
        return if @ports.include?(port)

        @ports << port
        @spatial_index.add(port)
      end

      def remove_port(port)
        return unless port

        @ports.delete(port)
        @spatial_index.remove(port)

        @connections.delete_if { |connection| connection.includes?(port) }
      end

      def connect_ports(port_a, port_b)
        return nil unless port_a && port_b
        return nil if port_a == port_b
        return existing_connection(port_a, port_b) if connected?(port_a, port_b)

        connection = Connection.new(port_a, port_b)
        @connections << connection
        connection
      end

      def disconnect_port(port)
        @connections.delete_if { |connection| connection.includes?(port) }
      end

      def connected?(port_a, port_b)
        !!existing_connection(port_a, port_b)
      end

      def existing_connection(port_a, port_b)
        @connections.find do |connection|
          (connection.port_a == port_a && connection.port_b == port_b) ||
            (connection.port_a == port_b && connection.port_b == port_a)
        end
      end

      def connected_ports(port)
        @connections.map do |connection|
          connection.other(port)
        end.compact
      end

      def external_connected?(port)
        connected_ports(port).any? do |other|
          other && other.piece != port.piece
        end
      end

      def open_external_port?(port)
        return false unless port
        return false unless port.piece
        return false unless port.piece.group && port.piece.group.valid?

        !external_connected?(port)
      end

      def open_external_ports
        @ports.select { |port| open_external_port?(port) }
      end

      def nearest_open_external_port(point, max_distance = SNAP_DISTANCE)
        candidates = nearby_ports(point, max_distance)

        candidates
          .select { |port| open_external_port?(port) }
          .min_by { |port| port.point.distance(point) }
      end

      def nearby_ports(point, radius)
        @spatial_index.nearby(point, radius)
      end

      def find_nearest_port(point, max_distance = SNAP_DISTANCE)
        nearby_ports(point, max_distance).min_by do |port|
          port.point.distance(point)
        end
      end

      def rebuild_index!
        @ports.delete_if do |port|
          !port ||
            !port.piece ||
            !port.piece.group ||
            !port.piece.group.valid?
        end

        @pieces.delete_if do |piece|
          !piece ||
            !piece.group ||
            !piece.group.valid?
        end

        @connections.delete_if do |connection|
          !connection.valid?
        end

        @spatial_index.rebuild(@ports)
      end

      def pieces_of_type(type)
        type = type.to_sym
        @pieces.select { |piece| piece.type == type }
      end

      def pipes
        pieces_of_type(:pipe)
      end

      def tees
        pieces_of_type(:tee)
      end

      def elbows
        pieces_of_type(:elbow)
      end
    end
  end
end

module DuctExtension
  module Model
    class Connection
      def includes_any?(ports)
        Array(ports).any? { |port| includes?(port) }
      end
    end
  end
end
