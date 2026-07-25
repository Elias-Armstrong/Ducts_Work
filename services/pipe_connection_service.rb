module DuctExtension
  module Services
    module PipeTargetConnectionService
      def self.insert_smart_tee_target(
        model:,
        network:,
        target_pipe_piece:,
        click_point:,
        active_start_point:,
        active_start_port: nil,
        active_dimensions: nil,
        requested_branch_direction: nil
      )
        return nil unless model && network
        return nil unless target_pipe_piece
        return nil unless target_pipe_piece.type == :pipe
        return nil unless target_pipe_piece.ports && target_pipe_piece.ports.length == 2
        return nil unless click_point && active_start_point

        port_a = target_pipe_piece.ports[0]
        port_b = target_pipe_piece.ports[1]
        dimensions = Model::Port.dimensions_from_params({}, port_a)

        requested_branch_dimensions =
          if active_start_port
            Model::Port.dimensions_from_params({}, active_start_port)
          elsif active_dimensions
            Model::DuctDimensions.coerce(active_dimensions, fallback: dimensions)
          else
            dimensions
          end

        placement = TeePlacementCalculator.best_placement(
          pipe_start: port_a.point,
          pipe_end: port_b.point,
          dimensions: dimensions,
          click_point: click_point,
          active_start_point: active_start_point,
          active_start_port: active_start_port,
          requested_branch_direction: requested_branch_direction,
          preferred_width_axis: port_a.width_axis || port_b.width_axis,
          preferred_height_axis: port_a.height_axis || port_b.height_axis
        )
        return nil unless placement

        TeeInsertService.insert_tee_on_pipe(
          model: model,
          network: network,
          pipe_piece: target_pipe_piece,
          tap_point: placement[:center],
          branch_direction: placement[:branch_vector],
          branch_dimensions: requested_branch_dimensions
        )
      rescue => error
        puts "PipeTargetConnectionService.insert_smart_tee_target failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end
    end
  end
end
