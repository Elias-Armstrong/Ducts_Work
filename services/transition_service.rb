# ===== Consolidated from: services/branch_size_prompt.rb =====
module DuctExtension
  module Services
    # Shared branch-size UI for fittings whose side outlet may differ from the
    # main duct. Keeping this here prevents wye/cross tools from drifting into
    # slightly different validation/default rules.
    module BranchSizePrompt
      def self.ask(main_dimensions:, title:, allow_round_from_rectangular: false)
        main = Model::DuctDimensions.coerce(main_dimensions)

        if Catalog::Manager.active?(Sketchup.active_model)
          family = title.to_s.downcase.include?("wye") ? :wye : :tee
          return Catalog::Manager.prompt_branch_dimensions(
            main_dimensions: main,
            family: family,
            title: title,
            model: Sketchup.active_model
          )
        end

        if main.round?
          input = ::UI.inputbox(
            ["Main Diameter:", "Branch Diameter:"],
            [main.diameter.to_s, main.diameter.to_s],
            [],
            title
          )
          return nil unless input

          return Model::DuctDimensions.round(
            diameter: Model::DuctDimensions.positive_number(input[1], main.diameter)
          )
        end

        if allow_round_from_rectangular
          input = ::UI.inputbox(
            [
              "Main Width:", "Main Height:", "Branch Shape:",
              "Round Branch Diameter:", "Rectangular Branch Width:", "Rectangular Branch Height:"
            ],
            [
              main.width.to_s, main.height.to_s, "Rectangular",
              main.largest.to_s, main.width.to_s, main.height.to_s
            ],
            ["", "", "Rectangular|Round", "", "", ""],
            title
          )
          return nil unless input

          if Model::DuctDimensions.normalize_shape(input[2]) == :round
            return Model::DuctDimensions.round(
              diameter: Model::DuctDimensions.positive_number(input[3], main.largest)
            )
          end

          return Model::DuctDimensions.rectangular(
            width: Model::DuctDimensions.positive_number(input[4], main.width),
            height: Model::DuctDimensions.positive_number(input[5], main.height)
          )
        end

        input = ::UI.inputbox(
          ["Main Width:", "Main Height:", "Branch Width:", "Branch Height:"],
          [main.width.to_s, main.height.to_s, main.width.to_s, main.height.to_s],
          [],
          title
        )
        return nil unless input

        Model::DuctDimensions.rectangular(
          width: Model::DuctDimensions.positive_number(input[2], main.width),
          height: Model::DuctDimensions.positive_number(input[3], main.height)
        )
      rescue => error
        puts "BranchSizePrompt.ask failed: #{error.message}"
        nil
      end
    end
  end
end

# ===== Consolidated from: services/branch_transition_service.rb =====
module DuctExtension
  module Services
    # Owns the small transition immediately after a fitting branch.
    #
    # Fittings stay geometrically conservative: their socket is never made
    # larger than the fitting's main body. If the requested branch is larger
    # (or changes shape), this service inserts the reducer/increaser/adapter
    # as a separate network piece and returns its open outer port.
    module BranchTransitionService
      TOLERANCE = 0.001

      def self.transition_needed?(source_dimensions, target_dimensions)
        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)

        source.shape != target.shape || !source.same_size?(target, tolerance: TOLERANCE)
      rescue
        false
      end

      # This method intentionally does not start/commit a SketchUp operation.
      # Callers use it inside the fitting's existing ModelOperation so inserting
      # a fitting + its transition remains one undoable action.
      def self.attach(
        model:,
        network:,
        source_port:,
        target_dimensions:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        cap_output: true,
        length: nil
      )
        return nil unless model && network && source_port

        source_dimensions = Model::Port.dimensions_from_params({}, source_port)
        target_dimensions = Model::DuctDimensions.coerce(
          target_dimensions,
          fallback: source_dimensions
        )

        unless transition_needed?(source_dimensions, target_dimensions)
          PortCapService.add(source_port.piece.group, source_port) if cap_output && source_port.piece
          return {
            piece: nil,
            input_port: source_port,
            output_port: source_port,
            source_dimensions: source_dimensions,
            target_dimensions: target_dimensions
          }
        end

        catalog_product = nil
        if Catalog::Manager.active?(model)
          catalog_product = Catalog::Manager.transition_product(source_dimensions, target_dimensions, model)
          return Catalog::Manager.notify_unsupported(:transition, source_dimensions) unless catalog_product
        end

        direction = Geometry::VectorMath.normalized(source_port.outward_vector)
        return nil unless direction

        length = length.to_f
        if catalog_product
          fallback_length = default_non_catalog_length(source_dimensions, target_dimensions)
          length = Catalog::Manager.transition_length(catalog_product, fallback_length)
        else
          length = default_branch_length(source_dimensions, target_dimensions) if length <= 0.0
        end
        return nil if length <= 0.0

        start_point = source_port.point
        end_point = start_point.offset(direction, length)

        basis_width =
          source_port.width_axis ||
          preferred_width_axis

        basis_height =
          source_port.height_axis ||
          preferred_height_axis

        group = model.active_entities.add_group
        group.name = catalog_product ? "Master Flow #{catalog_product.sku} — Transition" : transition_group_name(source_dimensions, target_dimensions)

        success =
          if catalog_product
            Catalog::MasterFlowGeometry.build_transition(
              group: group,
              start_point: start_point,
              end_point: end_point,
              start_dimensions: source_dimensions,
              end_dimensions: target_dimensions,
              product: catalog_product,
              preferred_width_axis: basis_width,
              preferred_height_axis: basis_height
            )
          else
            Geometry::ReducerBuilder.build_into(
              group,
              start_point,
              end_point,
              start_dimensions: source_dimensions,
              end_dimensions: target_dimensions,
              preferred_width_axis: basis_width,
              preferred_height_axis: basis_height
            )
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        start_basis = rectangular_basis_for_port(
          dimensions: source_dimensions,
          direction: direction.clone.reverse,
          preferred_width_axis: basis_width,
          preferred_height_axis: basis_height
        )

        end_basis = rectangular_basis_for_port(
          dimensions: target_dimensions,
          direction: direction,
          preferred_width_axis: preferred_width_axis || basis_width,
          preferred_height_axis: preferred_height_axis || basis_height
        )

        transition_input = Model::Port.new(
          point: start_point,
          vector: direction.clone.reverse,
          diameter: source_dimensions[:diameter],
          shape: source_dimensions[:shape],
          width: source_dimensions[:width],
          height: source_dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        transition_output = Model::Port.new(
          point: end_point,
          vector: direction,
          diameter: target_dimensions[:diameter],
          shape: target_dimensions[:shape],
          width: target_dimensions[:width],
          height: target_dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :reducer,
          group: group,
          ports: [transition_input, transition_output]
        )

        network.add_piece(piece)
        PieceMetadataService.save_piece(piece)
        Catalog::Manager.tag_piece(
          piece,
          catalog_product,
          "modeled_transition_length" => length
        ) if catalog_product
        network.connect_ports(source_port, transition_input)

        PortCapService.remove(source_port)
        PortCapService.add(group, transition_output) if cap_output
        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        {
          piece: piece,
          input_port: transition_input,
          output_port: transition_output,
          source_dimensions: source_dimensions,
          target_dimensions: target_dimensions,
          catalog_product: catalog_product
        }
      rescue => error
        puts "BranchTransitionService.attach failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end


      def self.default_branch_length(source_dimensions, target_dimensions)
        if Catalog::Manager.active?(Sketchup.active_model)
          product = Catalog::Manager.transition_product(source_dimensions, target_dimensions, Sketchup.active_model)
          return 0.0 unless product
          return Catalog::Manager.transition_length(
            product,
            default_non_catalog_length(source_dimensions, target_dimensions)
          )
        end

        default_non_catalog_length(source_dimensions, target_dimensions)
      rescue
        Geometry::ReducerBuilder.default_length(source_dimensions, target_dimensions).to_f
      end

      def self.default_non_catalog_length(source_dimensions, target_dimensions)
        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)

        largest = [source.largest, target.largest].max.to_f

        if source.shape != target.shape
          return [largest * 0.75, 4.0].max
        end

        delta =
          if source.round?
            (target.diameter - source.diameter).abs
          else
            [
              (target.width - source.width).abs,
              (target.height - source.height).abs
            ].max
          end

        [largest, delta * 2.0, 6.0].max
      rescue
        Geometry::ReducerBuilder.default_length(source_dimensions, target_dimensions).to_f
      end

      def self.rectangular_basis_for_port(
        dimensions:,
        direction:,
        preferred_width_axis:,
        preferred_height_axis:
      )
        return nil unless Model::DuctDimensions.coerce(dimensions).rectangular?

        Geometry::RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      rescue
        nil
      end
      private_class_method :rectangular_basis_for_port

      def self.transition_group_name(source_dimensions, target_dimensions)
        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)

        if source.shape != target.shape
          return source.rectangular? ? "Rectangular to Round Transition" : "Round to Rectangular Transition"
        end

        if source.round?
          return target.diameter > source.diameter ? "Round Branch Increaser" : "Round Branch Reducer"
        end

        source_area = source.width * source.height
        target_area = target.width * target.height

        target_area > source_area ? "Rectangular Branch Increaser" : "Rectangular Branch Reducer"
      rescue
        "Branch Transition"
      end
      private_class_method :transition_group_name
    end
  end
end

# ===== Consolidated from: services/end_reducer_insert_service.rb =====
module DuctExtension
  module Services
    class EndReducerInsertService
      def self.insert_at_port(
        model:,
        network:,
        stem_port:,
        new_shape: nil,
        new_diameter: nil,
        new_width: nil,
        new_height: nil,
        length: nil
      )
        return nil unless model && network && stem_port
        return nil unless stem_port.piece && stem_port.piece.group && stem_port.piece.group.valid?

        start_dimensions = Model::Port.dimensions_from_params({}, stem_port)
        end_dimensions = requested_dimensions(
          stem_port,
          start_dimensions,
          new_shape: new_shape,
          new_diameter: new_diameter,
          new_width: new_width,
          new_height: new_height
        )
        return nil unless valid_size_change?(start_dimensions, end_dimensions)

        ModelOperation.run(
          model: model,
          network: network,
          name: "Insert Increaser / Reducer"
        ) do |operation|
          transition = BranchTransitionService.attach(
            model: model,
            network: network,
            source_port: stem_port,
            target_dimensions: end_dimensions,
            preferred_width_axis: stem_port.width_axis,
            preferred_height_axis: stem_port.height_axis,
            cap_output: true,
            length: length
          )
          operation.abort!(nil) unless transition && transition[:piece]

          {
            piece: transition[:piece],
            old_port: transition[:input_port],
            new_port: transition[:output_port],
            start_dimensions: start_dimensions,
            end_dimensions: end_dimensions
          }
        end
      rescue => error
        puts "EndReducerInsertService.insert_at_port failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.requested_dimensions(stem_port, start_dimensions, new_shape:, new_diameter:, new_width:, new_height:)
        target_shape = new_shape ? Model::DuctDimensions.normalize_shape(new_shape) : start_dimensions[:shape]
        params =
          if target_shape == :rectangular
            { shape: :rectangular, width: new_width, height: new_height }
          else
            { shape: :round, diameter: new_diameter }
          end

        Model::Port.dimensions_from_params(params, stem_port)
      end
      private_class_method :requested_dimensions

      def self.valid_size_change?(start_dimensions, end_dimensions)
        return false unless start_dimensions && end_dimensions
        BranchTransitionService.transition_needed?(start_dimensions, end_dimensions)
      rescue
        false
      end
    end
  end
end
