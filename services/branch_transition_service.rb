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

      def self.socket_dimensions(main_dimensions:, requested_dimensions:)
        main = Model::DuctDimensions.coerce(main_dimensions)
        requested = Model::DuctDimensions.coerce(requested_dimensions, fallback: main)

        return main if main.shape != requested.shape

        if main.round?
          return requested if requested.diameter <= main.diameter + TOLERANCE
          return main
        end

        width = [requested.width, main.width].min
        height = [requested.height, main.height].min

        Model::DuctDimensions.rectangular(width: width, height: height)
      rescue
        Model::DuctDimensions.coerce(main_dimensions)
      end

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

        direction = Geometry::VectorMath.normalized(source_port.outward_vector)
        return nil unless direction

        length = length.to_f
        length = default_branch_length(source_dimensions, target_dimensions) if length <= 0.0
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
        group.name = transition_group_name(source_dimensions, target_dimensions)

        success = Geometry::ReducerBuilder.build_into(
          group,
          start_point,
          end_point,
          start_dimensions: source_dimensions,
          end_dimensions: target_dimensions,
          preferred_width_axis: basis_width,
          preferred_height_axis: basis_height
        )

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
        network.connect_ports(source_port, transition_input)

        PortCapService.remove(source_port)
        PortCapService.add(group, transition_output) if cap_output
        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        {
          piece: piece,
          input_port: transition_input,
          output_port: transition_output,
          source_dimensions: source_dimensions,
          target_dimensions: target_dimensions
        }
      rescue => error
        puts "BranchTransitionService.attach failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end


      def self.default_branch_length(source_dimensions, target_dimensions)
        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)

        largest = [source.largest, target.largest].max.to_f

        if source.shape != target.shape
          # Side-takeoff adapters should be squat, like a fabricated
          # square-to-round boot, rather than a long inline reducer.
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
