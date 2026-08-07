# ===== Consolidated from: services/end_tee_insert_service.rb =====
module DuctExtension
  module Services
    class EndTeeInsertService
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.82

      def self.insert_at_port(model:, network:, stem_port:, side_vector:)
        return nil unless model && network
        return nil unless stem_port
        return nil unless stem_port.piece
        return nil unless stem_port.piece.group && stem_port.piece.group.valid?

        dimensions = Model::Port.dimensions_from_params({}, stem_port)

        stem_out = stem_port.outward_vector.clone
        return nil if stem_out.length == 0

        stem_out.normalize!

        branch_axis = Geometry::VectorMath.perpendicularized(side_vector, stem_out)
        branch_axis ||= Geometry::VectorMath.fallback_perpendicular_axis(stem_out)
        return nil unless branch_axis

        branch_axis.normalize!

        socket_depth = EndFittingSupport.socket_depth(
          dimensions: dimensions,
          round_builder: Geometry::TeeBuilder,
          rectangular_builder: Geometry::RectangularTeeBuilder,
          fallback_factor: FALLBACK_SOCKET_DEPTH_FACTOR
        )

        main_width_axis = nil
        main_height_axis = nil
        branch_base = nil
        center = nil

        if dimensions[:shape] == :rectangular
          stem_into_tee = stem_out.clone.reverse

          # Preserve the incoming rectangular roll. The crossbar runs along the
          # stem port's width axis, so the crossbar's width direction should be
          # the stem axis and its height should stay aligned with the old port.
          main_basis = Geometry::RectangularFrame.basis_for_axis(
            branch_axis,
            preferred_width_axis: stem_into_tee,
            preferred_height_axis: stem_port.height_axis
          )
          return nil unless main_basis

          main_width_axis = main_basis[:width_axis]
          main_height_axis = main_basis[:height_axis]

          face_offset = EndFittingSupport.rectangular_face_offset_for_direction(
            direction: stem_into_tee,
            dimensions: dimensions,
            basis: main_basis
          )

          # For rectangular end tees, the stem branch begins on the face of the
          # crossbar, not exactly at the crossbar center. Move the crossbar center
          # far enough outward that the branch socket lands exactly on the old
          # pipe end.
          center = stem_port.point.offset(stem_out, socket_depth + face_offset)
          branch_base = center.offset(stem_into_tee, face_offset)
        else
          center = stem_port.point.offset(stem_out, socket_depth)
          branch_base = center
        end

        left_socket = center.offset(branch_axis.clone.reverse, socket_depth)
        right_socket = center.offset(branch_axis, socket_depth)
        stem_socket = stem_port.point

        stem_into_tee = stem_out.clone.reverse

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert End Tee"
        ) do |operation|

        group = model.active_entities.add_group
        group.name =
          if dimensions[:shape] == :rectangular
            "Rectangular End Tee"
          else
            "End Tee"
          end

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularTeeBuilder.build_into(
              group,
              center,
              branch_base,
              branch_axis,
              stem_into_tee,
              dimensions[:width],
              dimensions[:height],
              socket_depth,
              preferred_main_width_axis: main_width_axis,
              preferred_main_height_axis: main_height_axis
            )
          else
            Geometry::TeeBuilder.build_into(
              group,
              center,
              branch_axis,
              stem_into_tee,
              dimensions[:diameter]
            )
          end

        unless success
          group.erase! if group.valid?
          operation.abort!(nil)
        end

        left_basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              branch_axis.clone.reverse,
              preferred_width_axis: main_width_axis,
              preferred_height_axis: main_height_axis
            )
          end

        right_basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              branch_axis,
              preferred_width_axis: main_width_axis,
              preferred_height_axis: main_height_axis
            )
          end

        stem_basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              stem_into_tee,
              preferred_width_axis: stem_port.width_axis,
              preferred_height_axis: stem_port.height_axis
            )
          end

        left_port = Model::Port.new(
          point: left_socket,
          vector: branch_axis.clone.reverse,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: left_basis && left_basis[:width_axis],
          height_axis: left_basis && left_basis[:height_axis]
        )

        right_port = Model::Port.new(
          point: right_socket,
          vector: branch_axis.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: right_basis && right_basis[:width_axis],
          height_axis: right_basis && right_basis[:height_axis]
        )

        tee_stem_port = Model::Port.new(
          point: stem_socket,
          vector: stem_into_tee,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: stem_basis && stem_basis[:width_axis],
          height_axis: stem_basis && stem_basis[:height_axis]
        )

        tee_piece = Model::DuctPiece.new(
          type: :tee,
          group: group,
          ports: [left_port, right_port, tee_stem_port]
        )

        # End tee mode creates two available branches. Finalize the shared
        # network/metadata work and cap both outlets until one is used.
        EndFittingSupport.finalize_end_fitting!(
          network: network,
          original_stem_port: stem_port,
          piece: tee_piece,
          fitting_stem_port: tee_stem_port,
          outlet_ports: [left_port, right_port]
        )

        {
          tee_piece: tee_piece,

          # New clearer names.
          left_port: left_port,
          right_port: right_port,
          stem_port: tee_stem_port,

          # Compatibility names in case any older tool code expects these.
          main_start_port: left_port,
          main_end_port: right_port,
          branch_port: left_port
        }
        end
      rescue => error
        puts "EndTeeInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

    end
  end
end

# ===== Consolidated from: services/end_cross_insert_service.rb =====
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
        BranchSizePrompt.ask(
          main_dimensions: dimensions,
          title: "End Cross Branch Size",
          allow_round_from_rectangular: false
        )
      end

      private_class_method :prompt_for_branch_dimensions
    end
  end
end
