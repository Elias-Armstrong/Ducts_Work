module DuctExtension
  module Services
    class EndWyeInsertService
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.90

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
          dimensions: dimensions
        )

        return nil unless frame

        side_axis = frame[:side_axis]
        height_axis = frame[:height_axis]

        branch_axis = Geometry::WyeBuilder.branch_vector(forward_vector, side_axis)
        return nil unless branch_axis

        main_socket_distance = wye_main_socket_distance(dimensions)

        branch_socket_distance = wye_branch_socket_distance(
          main_dimensions: dimensions,
          branch_dimensions: branch_dimensions,
          branch_axis: branch_axis,
          side_axis: side_axis
        )

        center = stem_port.point.offset(forward_vector, wye_socket_depth(dimensions))

        stem_socket = stem_port.point
        forward_socket = center.offset(forward_vector, main_socket_distance)
        branch_socket = center.offset(branch_axis, branch_socket_distance)

        stem_into_wye = forward_vector.clone.reverse

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert End Wye"
        ) do |operation|

        group = model.active_entities.add_group
        group.name =
          if dimensions[:shape] == :rectangular
            "Rectangular End Wye"
          else
            "End Wye"
          end

        success = Geometry::WyeBuilder.build_into(
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
          branch_shape: branch_dimensions[:shape],
          branch_diameter: branch_dimensions[:diameter],
          branch_width: branch_dimensions[:width],
          branch_height: branch_dimensions[:height]
        )

        unless success
          group.erase! if group.valid?
          operation.abort!(nil)
        end

        branch_width_axis =
          if branch_dimensions[:shape] == :rectangular
            Geometry::VectorMath.perpendicularized(side_axis, branch_axis) ||
              Geometry::VectorMath.perpendicularized(forward_vector, branch_axis)
          else
            nil
          end

        branch_height_axis =
          if branch_dimensions[:shape] == :rectangular
            Geometry::VectorMath.perpendicularized(height_axis, branch_axis) ||
              begin
                axis = branch_axis.cross(branch_width_axis)
                axis.normalize! if axis && axis.length > 0
                axis
              end
          else
            nil
          end

        stem_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: dimensions,
          direction: stem_into_wye,
          width_axis: side_axis,
          height_axis: height_axis
        )

        forward_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: dimensions,
          direction: forward_vector,
          width_axis: side_axis,
          height_axis: height_axis
        )

        branch_basis = EndFittingSupport.port_basis_for_direction(
          dimensions: branch_dimensions,
          direction: branch_axis,
          width_axis: branch_width_axis,
          height_axis: branch_height_axis
        )

        wye_stem_port = Model::Port.new(
          point: stem_socket,
          vector: stem_into_wye,
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

        branch_port = Model::Port.new(
          point: branch_socket,
          vector: branch_axis,
          diameter: branch_dimensions[:diameter],
          shape: branch_dimensions[:shape],
          width: branch_dimensions[:width],
          height: branch_dimensions[:height],
          width_axis: branch_basis && branch_basis[:width_axis],
          height_axis: branch_basis && branch_basis[:height_axis]
        )

        wye_piece = Model::DuctPiece.new(
          type: :wye,
          group: group,
          ports: [forward_port, branch_port, wye_stem_port]
        )

        EndFittingSupport.finalize_end_fitting!(
          network: network,
          original_stem_port: stem_port,
          piece: wye_piece,
          fitting_stem_port: wye_stem_port,
          outlet_ports: [forward_port, branch_port]
        )

        {
          wye_piece: wye_piece,
          tee_piece: wye_piece,
          stem_port: wye_stem_port,
          forward_port: forward_port,
          branch_port: branch_port,
          main_start_port: forward_port,
          main_end_port: branch_port
        }
        end
      rescue => error
        puts "EndWyeInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.wye_socket_depth(dimensions)
        if dimensions[:shape] == :rectangular
          return Geometry::WyeBuilder.socket_depth(
            dimensions[:width],
            dimensions[:height]
          )
        end

        Geometry::WyeBuilder.socket_depth(dimensions[:diameter])
      rescue
        [
          dimensions[:diameter].to_f,
          dimensions[:width].to_f,
          dimensions[:height].to_f
        ].max * FALLBACK_SOCKET_DEPTH_FACTOR
      end

      def self.wye_main_socket_distance(dimensions)
        if dimensions[:shape] == :rectangular
          return Geometry::WyeBuilder.main_outlet_distance(
            dimensions[:width],
            dimensions[:height]
          )
        end

        Geometry::WyeBuilder.main_outlet_distance(dimensions[:diameter])
      rescue
        wye_socket_depth(dimensions)
      end

      def self.wye_branch_socket_distance(main_dimensions:, branch_dimensions:, branch_axis:, side_axis:)
        if main_dimensions[:shape] == :rectangular && branch_dimensions[:shape] == :round
          return Geometry::WyeBuilder.rectangular_round_branch_outlet_distance(
            main_dimensions[:width],
            main_dimensions[:height],
            branch_dimensions[:diameter],
            branch_axis,
            side_axis
          )
        end

        if branch_dimensions[:shape] == :rectangular
          return Geometry::WyeBuilder.branch_outlet_distance(
            branch_dimensions[:width],
            branch_dimensions[:height]
          )
        end

        Geometry::WyeBuilder.branch_outlet_distance(branch_dimensions[:diameter])
      rescue => error
        puts "EndWyeInsertService.wye_branch_socket_distance failed: #{error.message}"
        wye_socket_depth(branch_dimensions)
      end

      def self.prompt_for_branch_dimensions(dimensions)
        if dimensions[:shape] == :rectangular
          prompts = [
            "Main Width:",
            "Main Height:",
            "Branch Shape:",
            "Round Branch Diameter:",
            "Rectangular Branch Width:",
            "Rectangular Branch Height:"
          ]

          defaults = [
            dimensions[:width].to_s,
            dimensions[:height].to_s,
            "Rectangular",
            [dimensions[:width].to_f, dimensions[:height].to_f].max.to_s,
            dimensions[:width].to_s,
            dimensions[:height].to_s
          ]

          lists = ["", "", "Rectangular|Round", "", "", ""]

          input = ::UI.inputbox(prompts, defaults, lists, "End Wye Branch Size")
          return nil unless input

          branch_shape = Model::DuctDimensions.normalize_shape(input[2])

          if branch_shape == :round
            branch_diameter = Model::DuctDimensions.positive_number(input[3], [dimensions[:width].to_f, dimensions[:height].to_f].max)
            {
              shape: :round,
              diameter: branch_diameter,
              width: branch_diameter,
              height: branch_diameter
            }
          else
            branch_width = Model::DuctDimensions.positive_number(input[4], dimensions[:width])
            branch_height = Model::DuctDimensions.positive_number(input[5], dimensions[:height])
            {
              shape: :rectangular,
              diameter: [branch_width, branch_height].max,
              width: branch_width,
              height: branch_height
            }
          end
        else
          prompts = ["Main Diameter:", "Branch Diameter:"]
          defaults = [dimensions[:diameter].to_s, dimensions[:diameter].to_s]
          input = ::UI.inputbox(prompts, defaults, [], "End Wye Branch Size")
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
        puts "EndWyeInsertService.prompt_for_branch_dimensions failed: #{error.message}"
        nil
      end

      private_class_method :wye_socket_depth
      private_class_method :wye_main_socket_distance
      private_class_method :wye_branch_socket_distance
      private_class_method :prompt_for_branch_dimensions
    end
  end
end
