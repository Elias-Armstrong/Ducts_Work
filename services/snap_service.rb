module DuctExtension
  module Services
    module SnapService
      # Old value was 14 px. That was too precise for crosses/tees because the
      # open ports are close together and often partly hidden by the fitting hub.
      #
      # This larger snap radius makes the tool much friendlier:
      # - easier to continue from crosses
      # - easier to grab tee branches
      # - easier to connect into open pipe ends
      #
      # If snapping later feels too aggressive, try 28 or 32.
      PICK_RADIUS_PIXELS = 38

      # Pipe-body clicking should stay tighter than open-port snapping. If this
      # is too large, clicking near a port can accidentally target the pipe body
      # and insert a tee instead of snapping to the open port.
      PIPE_PICK_RADIUS_PIXELS = 10

      # If several open ports are near the click, prefer the closest screen-space
      # port, but add a small bias toward ports that are physically closer to the
      # provided 3D point. This helps with dense fittings like crosses.
      WORLD_DISTANCE_SCORE_FACTOR = 0.15

      def self.find_open_external_port(network:, view:, x:, y:, point:)
        return nil unless network && view && point

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        candidates = network.open_external_ports
        return nil if candidates.empty?

        best = nil
        best_screen_distance = nil
        best_score = nil

        candidates.each do |port|
          next unless port && port.point
          next unless port.piece
          next unless port.piece.group && port.piece.group.valid?

          screen_point = view.screen_coords(port.point)
          screen_distance = screen_distance(screen_point, x, y)

          next if screen_distance > PICK_RADIUS_PIXELS

          world_distance =
            begin
              port.point.distance(point)
            rescue
              0.0
            end

          score = screen_distance + (world_distance * WORLD_DISTANCE_SCORE_FACTOR)

          if best.nil? || score < best_score
            best = port
            best_screen_distance = screen_distance
            best_score = score
          end
        end

        return nil unless best

        SnapResult.new(best, best_screen_distance)
      rescue => error
        puts "SnapService.find_open_external_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.picked_pipe_piece(network:, view:, x:, y:)
        return nil unless network && view

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        best_piece = nil
        best_distance = nil

        network.pipes.each do |piece|
          next unless piece && piece.group && piece.group.valid?
          next unless piece.ports && piece.ports.length == 2

          port_a = piece.ports[0]
          port_b = piece.ports[1]

          next unless port_a && port_b
          next unless port_a.point && port_b.point

          screen_a = view.screen_coords(port_a.point)
          screen_b = view.screen_coords(port_b.point)

          distance = point_to_screen_segment_distance(
            x.to_f,
            y.to_f,
            screen_a.x.to_f,
            screen_a.y.to_f,
            screen_b.x.to_f,
            screen_b.y.to_f
          )

          next if distance > PIPE_PICK_RADIUS_PIXELS

          if best_piece.nil? || distance < best_distance
            best_piece = piece
            best_distance = distance
          end
        end

        best_piece
      rescue => error
        puts "SnapService.picked_pipe_piece failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.screen_distance(screen_point, x, y)
        dx = screen_point.x.to_f - x.to_f
        dy = screen_point.y.to_f - y.to_f

        Math.sqrt(dx * dx + dy * dy)
      end

      def self.point_to_screen_segment_distance(px, py, ax, ay, bx, by)
        abx = bx - ax
        aby = by - ay

        length_squared = abx * abx + aby * aby

        if length_squared <= 0.000001
          dx = px - ax
          dy = py - ay
          return Math.sqrt(dx * dx + dy * dy)
        end

        apx = px - ax
        apy = py - ay

        t = (apx * abx + apy * aby) / length_squared
        t = [[t, 0.0].max, 1.0].min

        closest_x = ax + abx * t
        closest_y = ay + aby * t

        dx = px - closest_x
        dy = py - closest_y

        Math.sqrt(dx * dx + dy * dy)
      end

      class SnapResult
        attr_reader :port
        attr_reader :screen_distance

        def initialize(port, screen_distance)
          @port = port
          @screen_distance = screen_distance
        end
      end
    end
  end
end
