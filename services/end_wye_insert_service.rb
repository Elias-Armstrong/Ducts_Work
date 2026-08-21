module DuctExtension
  module Services
    class EndWyeInsertService
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.90

      def self.insert_at_port(model:, network:, stem_port:, side_vector:)
        return nil unless model && network
        return nil unless stem_port
        return nil unless stem_port.piece
        return nil unless stem_port.piece.group && stem_port.piece.group.valid?

        main_dimensions = Model::Port.dimensions_from_params({}, stem_port)

        if Catalog::Manager.active?(model)
          return insert_catalog_wye(
            model: model,
            network: network,
            stem_port: stem_port,
            side_vector: side_vector,
            main_dimensions: main_dimensions
          )
        end

        catalog_product = nil
        requested_branch_dimensions = prompt_for_branch_dimensions(main_dimensions)
        return nil unless requested_branch_dimensions

        forward_vector = Geometry::VectorMath.normalized(stem_port.outward_vector)
        return nil unless forward_vector

        frame = EndFittingSupport.frame_for_stem_port(
          stem_port: stem_port,
          side_vector: side_vector,
          forward_vector: forward_vector,
          dimensions: main_dimensions
        )
        return nil unless frame

        side_axis = frame[:side_axis]
        height_axis = frame[:height_axis]

        mixed_side_takeoff =
          main_dimensions[:shape] == :rectangular &&
          requested_branch_dimensions[:shape] == :round

        # Keep the wye body geometrically stable: its branch socket always uses
        # the main duct's own cross-section. Any requested branch size/shape
        # change is handled immediately after the fitting by
        # BranchTransitionService. This mirrors TeeInsertService and avoids
        # fragile small/large branch geometry inside the wye body itself.
        native_branch_dimensions = Model::DuctDimensions.coerce(main_dimensions)

        layout =
          if mixed_side_takeoff
            mixed_rectangular_round_layout(
              stem_port: stem_port,
              forward_vector: forward_vector,
              side_axis: side_axis,
              height_axis: height_axis,
              dimensions: main_dimensions
            )
          else
            standard_wye_layout(
              stem_port: stem_port,
              forward_vector: forward_vector,
              side_axis: side_axis,
              height_axis: height_axis,
              main_dimensions: main_dimensions,
              branch_dimensions: native_branch_dimensions
            )
          end
        return nil unless layout

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert End Wye"
        ) do |operation|
          group = model.active_entities.add_group
          group.name =
            if catalog_product
              "#{Catalog::Manager.product_catalog_name(catalog_product)} #{catalog_product.sku} — End Wye"
            elsif mixed_side_takeoff
              "Rectangular to Round Side Takeoff"
            elsif main_dimensions[:shape] == :rectangular
              "Rectangular End Wye"
            else
              "End Wye"
            end

          success =
            if mixed_side_takeoff
              Geometry::RectangularTeeBuilder.build_into(
                group,
                layout[:center],
                layout[:branch_base],
                forward_vector,
                layout[:branch_axis],
                main_dimensions[:width],
                main_dimensions[:height],
                layout[:main_socket_depth],
                branch_depth: layout[:branch_stub_depth],
                preferred_main_width_axis: side_axis,
                preferred_main_height_axis: height_axis
              )
            else
              Geometry::WyeBuilder.build_into(
                group,
                layout[:center],
                forward_vector,
                side_axis,
                diameter: main_dimensions[:diameter],
                width: main_dimensions[:width],
                height: main_dimensions[:height],
                shape: main_dimensions[:shape],
                preferred_width_axis: side_axis,
                preferred_height_axis: height_axis,
                branch_shape: native_branch_dimensions[:shape],
                branch_diameter: native_branch_dimensions[:diameter],
                branch_width: native_branch_dimensions[:width],
                branch_height: native_branch_dimensions[:height]
              )
            end

          unless success
            group.erase! if group.valid?
            operation.abort!(nil)
          end

          stem_into_fitting = forward_vector.clone.reverse

          stem_basis = EndFittingSupport.port_basis_for_direction(
            dimensions: main_dimensions,
            direction: stem_into_fitting,
            width_axis: side_axis,
            height_axis: height_axis
          )

          forward_basis = EndFittingSupport.port_basis_for_direction(
            dimensions: main_dimensions,
            direction: forward_vector,
            width_axis: side_axis,
            height_axis: height_axis
          )

          branch_basis = branch_basis_for(
            branch_dimensions: native_branch_dimensions,
            branch_axis: layout[:branch_axis],
            side_axis: side_axis,
            height_axis: height_axis,
            forward_vector: forward_vector,
            mixed_side_takeoff: mixed_side_takeoff
          )

          fitting_stem_port = build_port(
            point: layout[:stem_socket],
            direction: stem_into_fitting,
            dimensions: main_dimensions,
            basis: stem_basis
          )

          forward_port = build_port(
            point: layout[:forward_socket],
            direction: forward_vector,
            dimensions: main_dimensions,
            basis: forward_basis
          )

          native_branch_port = build_port(
            point: layout[:branch_socket],
            direction: layout[:branch_axis],
            dimensions: native_branch_dimensions,
            basis: branch_basis
          )

          # Keep the semantic type as :wye even when the mixed-shape branch
          # uses the cleaner side-takeoff geometry. Swing/resize code detects
          # the actual branch angle from the ports and preserves that layout.
          piece = Model::DuctPiece.new(
            type: :wye,
            group: group,
            ports: [forward_port, native_branch_port, fitting_stem_port]
          )

          # The straight outlet belongs to the wye itself. The branch outlet is
          # deliberately left uncapped here because BranchTransitionService owns
          # everything after that socket:
          #
          #   same size      -> cap native branch once
          #   changed size   -> attach reducer/increaser and cap its outer end
          #
          # Keeping one owner prevents duplicate circular cap geometry.
          EndFittingSupport.finalize_end_fitting!(
            network: network,
            original_stem_port: stem_port,
            piece: piece,
            fitting_stem_port: fitting_stem_port,
            outlet_ports: [forward_port]
          )
          Catalog::Manager.tag_piece(piece, catalog_product) if catalog_product

          transition = BranchTransitionService.attach(
            model: model,
            network: network,
            source_port: native_branch_port,
            target_dimensions: requested_branch_dimensions,
            preferred_width_axis: branch_basis && branch_basis[:width_axis],
            preferred_height_axis: branch_basis && branch_basis[:height_axis],
            cap_output: true
          )

          operation.abort!(nil) unless transition

          {
            wye_piece: piece,
            tee_piece: piece,
            stem_port: fitting_stem_port,
            forward_port: forward_port,
            branch_port: transition[:output_port],
            native_branch_port: native_branch_port,
            branch_transition_piece: transition[:piece],
            main_start_port: forward_port,
            main_end_port: transition[:output_port]
          }
        end
      rescue => error
        puts "EndWyeInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.insert_catalog_wye(model:, network:, stem_port:, side_vector:, main_dimensions:)
        return Catalog::Manager.notify_unsupported(:wye, main_dimensions) unless main_dimensions[:shape] == :round

        product = Catalog::Manager.prompt_junction_product(
          main_dimensions: main_dimensions,
          family: :wye,
          title: "#{Catalog::Manager.active_name(model)} Wye",
          model: model
        )
        return nil unless product

        forward_vector = Geometry::VectorMath.normalized(stem_port.outward_vector)
        return nil unless forward_vector

        frame = EndFittingSupport.frame_for_stem_port(
          stem_port: stem_port,
          side_vector: side_vector,
          forward_vector: forward_vector,
          dimensions: main_dimensions
        )
        return nil unless frame

        layout = Catalog::MasterFlowGeometry.wye_layout(
          stem_point: stem_port.point,
          forward_vector: forward_vector,
          side_axis: frame[:side_axis],
          product: product
        )
        return nil unless layout

        output_dimensions = Catalog::Manager.wye_output_dimensions(product)
        return nil unless output_dimensions
        stem_into_fitting = forward_vector.clone.reverse

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert #{Catalog::Manager.active_name(model)} Wye"
        ) do |operation|
          group = model.active_entities.add_group
          group.name = "#{Catalog::Manager.product_catalog_name(product)} #{product.sku} — Wye"

          success = Catalog::MasterFlowGeometry.build_round_wye(
            group: group,
            layout: layout,
            product: product
          )
          unless success
            group.erase! if group.valid?
            operation.abort!(nil)
          end

          fitting_stem_port = Model::Port.new(
            point: layout[:stem_socket],
            vector: stem_into_fitting,
            diameter: main_dimensions[:diameter],
            shape: :round,
            width: main_dimensions[:diameter],
            height: main_dimensions[:diameter]
          )

          forward_port = Model::Port.new(
            point: layout[:forward_socket],
            vector: forward_vector,
            diameter: output_dimensions.diameter,
            shape: :round,
            width: output_dimensions.diameter,
            height: output_dimensions.diameter
          )

          branch_port = Model::Port.new(
            point: layout[:branch_socket],
            vector: layout[:branch_axis],
            diameter: output_dimensions.diameter,
            shape: :round,
            width: output_dimensions.diameter,
            height: output_dimensions.diameter
          )

          piece = Model::DuctPiece.new(
            type: :wye,
            group: group,
            ports: [forward_port, branch_port, fitting_stem_port]
          )

          EndFittingSupport.finalize_end_fitting!(
            network: network,
            original_stem_port: stem_port,
            piece: piece,
            fitting_stem_port: fitting_stem_port,
            outlet_ports: [forward_port, branch_port]
          )
          Catalog::Manager.tag_piece(
            piece,
            product,
            "catalog_rigid" => true,
            "integral_outlet_diameter" => output_dimensions.diameter
          )

          {
            wye_piece: piece,
            tee_piece: piece,
            stem_port: fitting_stem_port,
            forward_port: forward_port,
            branch_port: branch_port,
            native_branch_port: branch_port,
            branch_transition_piece: nil,
            main_start_port: forward_port,
            main_end_port: branch_port
          }
        end
      rescue => error
        puts "EndWyeInsertService.insert_catalog_wye failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end
      private_class_method :insert_catalog_wye

      def self.standard_wye_layout(
        stem_port:,
        forward_vector:,
        side_axis:,
        height_axis:,
        main_dimensions:,
        branch_dimensions:
      )
        branch_axis = Geometry::WyeBuilder.branch_vector(forward_vector, side_axis)
        return nil unless branch_axis

        center = stem_port.point.offset(forward_vector, wye_socket_depth(main_dimensions))

        {
          center: center,
          stem_socket: stem_port.point,
          forward_socket: center.offset(forward_vector, wye_main_socket_distance(main_dimensions)),
          branch_socket: center.offset(
            branch_axis,
            wye_branch_socket_distance(branch_dimensions)
          ),
          branch_axis: branch_axis,
          main_socket_depth: wye_socket_depth(main_dimensions)
        }
      rescue
        nil
      end
      private_class_method :standard_wye_layout

      def self.mixed_rectangular_round_layout(
        stem_port:,
        forward_vector:,
        side_axis:,
        height_axis:,
        dimensions:
      )
        main_socket_depth = Geometry::RectangularTeeBuilder.socket_depth(
          dimensions[:width],
          dimensions[:height]
        )

        center = stem_port.point.offset(forward_vector, main_socket_depth)
        branch_axis = side_axis.clone
        branch_axis.normalize!

        main_basis = {
          width_axis: side_axis,
          height_axis: height_axis
        }

        face_offset = EndFittingSupport.rectangular_face_offset_for_direction(
          direction: branch_axis,
          dimensions: dimensions,
          basis: main_basis
        )

        branch_base = center.offset(branch_axis, face_offset)
        branch_stub_depth = Geometry::RectangularTeeBuilder.side_takeoff_branch_depth(
          dimensions[:width],
          dimensions[:height]
        )

        {
          center: center,
          stem_socket: stem_port.point,
          forward_socket: center.offset(forward_vector, main_socket_depth),
          branch_base: branch_base,
          branch_socket: branch_base.offset(branch_axis, branch_stub_depth),
          branch_axis: branch_axis,
          main_socket_depth: main_socket_depth,
          branch_stub_depth: branch_stub_depth
        }
      rescue
        nil
      end
      private_class_method :mixed_rectangular_round_layout

      def self.branch_basis_for(
        branch_dimensions:,
        branch_axis:,
        side_axis:,
        height_axis:,
        forward_vector:,
        mixed_side_takeoff:
      )
        return nil unless branch_dimensions[:shape] == :rectangular

        if mixed_side_takeoff
          return Geometry::RectangularTeeBuilder.branch_basis(
            forward_vector,
            branch_axis,
            main_basis: {
              width_axis: side_axis,
              height_axis: height_axis
            }
          )
        end

        width_axis =
          Geometry::VectorMath.perpendicularized(side_axis, branch_axis) ||
          Geometry::VectorMath.perpendicularized(forward_vector, branch_axis)

        height_axis_for_branch =
          Geometry::VectorMath.perpendicularized(height_axis, branch_axis) ||
          begin
            axis = branch_axis.cross(width_axis)
            axis.normalize! if axis && axis.length > 0
            axis
          end

        {
          width_axis: width_axis,
          height_axis: height_axis_for_branch
        }
      rescue
        nil
      end
      private_class_method :branch_basis_for

      def self.build_port(point:, direction:, dimensions:, basis: nil)
        Model::Port.new(
          point: point,
          vector: direction,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: basis && basis[:width_axis],
          height_axis: basis && basis[:height_axis]
        )
      end
      private_class_method :build_port

      def self.wye_socket_depth(dimensions)
        if dimensions[:shape] == :rectangular
          return Geometry::WyeBuilder.socket_depth(
            dimensions[:width],
            dimensions[:height]
          )
        end

        Geometry::WyeBuilder.socket_depth(dimensions[:diameter])
      rescue
        Model::DuctDimensions.coerce(dimensions).largest * FALLBACK_SOCKET_DEPTH_FACTOR
      end
      private_class_method :wye_socket_depth

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
      private_class_method :wye_main_socket_distance

      def self.wye_branch_socket_distance(branch_dimensions)
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
      private_class_method :wye_branch_socket_distance

      def self.prompt_for_branch_dimensions(dimensions)
        BranchSizePrompt.ask(
          main_dimensions: dimensions,
          title: "End Wye Branch Size",
          allow_round_from_rectangular: true
        )
      end

      private_class_method :prompt_for_branch_dimensions
    end
  end
end
