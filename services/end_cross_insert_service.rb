module DuctExtension
  module Services
    class EndCrossInsertService
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.82

      def self.insert_at_port(model:, network:, stem_port:, side_vector:)
        return nil unless model && network
        return nil unless stem_port
        return nil unless stem_port.piece
        return nil unless stem_port.piece.group && stem_port.piece.group.valid?

        dimensions = Model::Port.dimensions_from_params({}, stem_port)
        branch_dimensions = prompt_for_branch_dimensions(dimensions)
        return nil unless branch_dimensions

        forward_vector = stem_port.outward_vector.clone
        return nil if forward_vector.length == 0
        forward_vector.normalize!

        frame = EndFittingSupport.frame_for_stem_port(
          stem_port: stem_port,
          side_vector: side_vector,
          forward_vector: forward_vector,
          dimensions: dimensions,
          reclean_rectangular_axes: true
        )

        return nil unless frame

        side_axis = frame[:side_axis]
        height_axis = frame[:height_axis]

        socket_depth = EndFittingSupport.socket_depth(
          dimensions: Model::DuctDimensions.max_dimensions(dimensions, branch_dimensions),
          round_builder: Geometry::CrossBuilder,
          fallback_factor: FALLBACK_SOCKET_DEPTH_FACTOR
        )
        center = stem_port.point.offset(forward_vector, socket_depth)

        stem_socket = stem_port.point
        forward_socket = center.offset(forward_vector, socket_depth)
        left_socket = center.offset(side_axis.clone.reverse, socket_depth)
        right_socket = center.offset(side_axis, socket_depth)

        stem_into_cross = forward_vector.clone.reverse

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert End Cross"
        ) do |operation|

        group = model.active_entities.add_group
        group.name =
          if dimensions[:shape] == :rectangular
            "Rectangular End Cross"
          else
            "End Cross"
          end

        success = Geometry::CrossBuilder.build_into(
          group,
          center,
          forward_vector,
          side_axis,
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          shape: dimensions[:shape],
          preferred_width_axis: side_axis,
          preferred_height_axis: height_axis,
          branch_diameter: branch_dimensions[:diameter],
          branch_width: branch_dimensions[:width],
          branch_height: branch_dimensions[:height]
        )

        unless success
          group.erase! if group.valid?
          operation.abort!(nil)
        end

        stem_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: dimensions,
          direction: stem_into_cross,
          width_axis: side_axis,
          height_axis: height_axis
        )

        forward_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: dimensions,
          direction: forward_vector,
          width_axis: side_axis,
          height_axis: height_axis
        )

        left_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: branch_dimensions,
          direction: side_axis.clone.reverse,
          width_axis: forward_vector,
          height_axis: height_axis
        )

        right_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: branch_dimensions,
          direction: side_axis,
          width_axis: forward_vector,
          height_axis: height_axis
        )

        cross_stem_port = Model::Port.new(
          point: stem_socket,
          vector: stem_into_cross,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: stem_basis && stem_basis[:width_axis],
          height_axis: stem_basis && stem_basis[:height_axis]
        )

        forward_port = Model::Port.new(
          point: forward_socket,
          vector: forward_vector,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: forward_basis && forward_basis[:width_axis],
          height_axis: forward_basis && forward_basis[:height_axis]
        )

        left_port = Model::Port.new(
          point: left_socket,
          vector: side_axis.clone.reverse,
          diameter: branch_dimensions[:diameter],
          shape: branch_dimensions[:shape],
          width: branch_dimensions[:width],
          height: branch_dimensions[:height],
          width_axis: left_basis && left_basis[:width_axis],
          height_axis: left_basis && left_basis[:height_axis]
        )

        right_port = Model::Port.new(
          point: right_socket,
          vector: side_axis,
          diameter: branch_dimensions[:diameter],
          shape: branch_dimensions[:shape],
          width: branch_dimensions[:width],
          height: branch_dimensions[:height],
          width_axis: right_basis && right_basis[:width_axis],
          height_axis: right_basis && right_basis[:height_axis]
        )

        cross_piece = Model::DuctPiece.new(
          type: :cross,
          group: group,
          ports: [left_port, right_port, forward_port, cross_stem_port]
        )

        EndFittingSupport.finalize_end_fitting!(
          network: network,
          original_stem_port: stem_port,
          piece: cross_piece,
          fitting_stem_port: cross_stem_port,
          outlet_ports: [left_port, right_port, forward_port]
        )

        {
          cross_piece: cross_piece,
          tee_piece: cross_piece,
          stem_port: cross_stem_port,
          left_port: left_port,
          right_port: right_port,
          forward_port: forward_port,
          main_start_port: left_port,
          main_end_port: right_port,
          branch_port: forward_port
        }
        end
      rescue => error
        puts "EndCrossInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.prompt_for_branch_dimensions(dimensions)
        if dimensions[:shape] == :rectangular
          prompts = [
            "Main Width:",
            "Main Height:",
            "Branch Width:",
            "Branch Height:"
          ]

          defaults = [
            dimensions[:width].to_s,
            dimensions[:height].to_s,
            dimensions[:width].to_s,
            dimensions[:height].to_s
          ]

          input = ::UI.inputbox(prompts, defaults, [], "End Cross Branch Size")
          return nil unless input

          branch_width = Model::DuctDimensions.positive_number(input[2], dimensions[:width])
          branch_height = Model::DuctDimensions.positive_number(input[3], dimensions[:height])

          {
            shape: :rectangular,
            diameter: [branch_width, branch_height].max,
            width: branch_width,
            height: branch_height
          }
        else
          prompts = ["Main Diameter:", "Branch Diameter:"]
          defaults = [dimensions[:diameter].to_s, dimensions[:diameter].to_s]
          input = ::UI.inputbox(prompts, defaults, [], "End Cross Branch Size")
          return nil unless input

          branch_diameter = Model::DuctDimensions.positive_number(input[1], dimensions[:diameter])

          {
            shape: :round,
            diameter: branch_diameter,
            width: branch_diameter,
            height: branch_diameter
          }
        end
      rescue => error
        puts "EndCrossInsertService.prompt_for_branch_dimensions failed: #{error.message}"
        nil
      end

      private_class_method :prompt_for_branch_dimensions
    end
  end
end
