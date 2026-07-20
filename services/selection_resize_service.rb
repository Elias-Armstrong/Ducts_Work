module DuctExtension
  module Services
    class SelectionResizeService
      EPSILON = 0.000001
      CONNECTION_TOLERANCE = 0.05

      SUPPORTED_TYPES = [
        :pipe,
        :elbow,
        :reducer
      ].freeze

      def self.run(model:, network:)
        return false unless model

        network = Services::NetworkRebuildService.rebuild(model)

        selected_pieces = selected_duct_pieces(model, network)

        if selected_pieces.empty?
          UI.messagebox(
            "Select one or more duct pieces first.\n\n" \
            "This first version supports selected straight pipes, elbows, and reducers."
          )
          return false
        end

        unsupported = selected_pieces.reject { |piece| SUPPORTED_TYPES.include?(piece.type.to_sym) }

        unless unsupported.empty?
          types = unsupported.map { |piece| piece.type.to_s }.uniq.sort.join(", ")

          UI.messagebox(
            "Resize Selected Duct Pieces currently supports pipes, elbows, and reducers.\n\n" \
            "Your selection includes unsupported fitting types:\n\n#{types}\n\n" \
            "Deselect tees/crosses/wyes for this first version."
          )

          return false
        end

        shape = common_shape_for(selected_pieces)

        unless shape
          UI.messagebox(
            "Please select only one duct shape at a time.\n\n" \
            "Do not mix round and rectangular duct pieces in the same resize operation."
          )
          return false
        end

        target_dimensions = prompt_for_target_dimensions(shape, selected_pieces)
        return false unless target_dimensions

        model.start_operation("Resize Selected Duct Pieces", true)

        selected_set = selected_pieces.each_with_object({}) { |piece, hash| hash[piece.object_id] = true }

        old_dimensions_by_piece = {}
        selected_pieces.each do |piece|
          old_dimensions_by_piece[piece.object_id] = dimensions_for_piece(piece)
        end

        adjust_selected_layout_for_size_change!(
          network: network,
          selected_pieces: selected_pieces,
          selected_set: selected_set,
          old_dimensions_by_piece: old_dimensions_by_piece,
          target_dimensions: target_dimensions
        )

        boundary_connections = selected_boundary_connections(network, selected_pieces)

        boundary_plan = build_boundary_plan(
          boundary_connections: boundary_connections,
          selected_set: selected_set,
          target_dimensions: target_dimensions
        )

        apply_boundary_pullbacks!(boundary_plan)

        selected_pieces.each do |piece|
          success = rebuild_selected_piece!(
            piece: piece,
            target_dimensions: target_dimensions
          )

          unless success
            model.abort_operation

            UI.messagebox(
              "Resize failed while rebuilding a #{piece.type}.\n\n" \
              "No changes were committed.\n\n" \
              "Check the Ruby Console for the exact elbow/vector details."
            )

            return false
          end
        end

        boundary_plan.each do |item|
          insert_boundary_reducer!(
            model: model,
            network: network,
            selected_port: item[:selected_port],
            external_port: item[:external_port],
            selected_dimensions: target_dimensions,
            external_dimensions: item[:external_dimensions]
          )
        end

        selected_pieces.each do |piece|
          PieceMetadataService.save_piece(piece)
        end

        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        model.commit_operation

        UI.messagebox(
          "Resized #{selected_pieces.length} selected duct piece(s).\n\n" \
          "Inserted #{boundary_plan.length} automatic reducer/increaser fitting(s) at selected-to-unselected boundaries."
        )

        true
      rescue => error
        model.abort_operation if model

        puts "SelectionResizeService.run failed: #{error.message}"
        puts error.backtrace.join("\n")

        UI.messagebox(
          "Resize Selected Duct Pieces failed.\n\n" \
          "Check the Ruby Console for details."
        )

        false
      end

      def self.selected_duct_pieces(model, network)
        selected_entities = model.selection.to_a

        selected_groups = selected_entities.select do |entity|
          entity.respond_to?(:get_attribute)
        end

        network.pieces.select do |piece|
          piece &&
            piece.group &&
            piece.group.valid? &&
            selected_groups.include?(piece.group)
        end
      rescue
        []
      end

      def self.common_shape_for(pieces)
        shapes = pieces.flat_map do |piece|
          Array(piece.ports).map do |port|
            Model::Port.normalize_shape_value(port.shape)
          end
        end.compact.uniq

        return nil if shapes.empty?
        return nil if shapes.length > 1

        shapes.first
      rescue
        nil
      end

      def self.prompt_for_target_dimensions(shape, selected_pieces)
        sample_port = selected_pieces.flat_map(&:ports).compact.first
        current = dimensions_for_port(sample_port)

        if shape == :rectangular
          prompts = [
            "New Width:",
            "New Height:"
          ]

          defaults = [
            current[:width].to_s,
            current[:height].to_s
          ]

          input = UI.inputbox(
            prompts,
            defaults,
            [],
            "Resize Selected Rectangular Duct"
          )

          return nil unless input

          width = positive_number(input[0], nil)
          height = positive_number(input[1], nil)

          unless width && height
            UI.messagebox("Please enter a valid width and height.")
            return nil
          end

          {
            shape: :rectangular,
            diameter: [width, height].max,
            width: width,
            height: height
          }
        else
          prompts = [
            "New Diameter:"
          ]

          defaults = [
            current[:diameter].to_s
          ]

          input = UI.inputbox(
            prompts,
            defaults,
            [],
            "Resize Selected Round Duct"
          )

          return nil unless input

          diameter = positive_number(input[0], nil)

          unless diameter
            UI.messagebox("Please enter a valid diameter.")
            return nil
          end

          {
            shape: :round,
            diameter: diameter,
            width: diameter,
            height: diameter
          }
        end
      rescue => error
        puts "SelectionResizeService.prompt_for_target_dimensions failed: #{error.message}"
        nil
      end

      def self.adjust_selected_layout_for_size_change!(
        network:,
        selected_pieces:,
        selected_set:,
        old_dimensions_by_piece:,
        target_dimensions:
      )
        moved_points = {}

        selected_pieces.each do |piece|
          next unless piece
          next unless piece.type.to_sym == :elbow

          old_dimensions = old_dimensions_by_piece[piece.object_id]
          next unless old_dimensions

          old_size = largest_size(old_dimensions)
          new_size = largest_size(target_dimensions)

          delta = new_size.to_f - old_size.to_f
          next if delta.abs <= EPSILON

          offset = delta / 2.0

          Array(piece.ports).each do |port|
            next unless port && port.point && port.outward_vector

            direction = port.outward_vector.clone
            next if direction.length <= EPSILON

            direction.normalize!

            new_point = port.point.offset(direction, offset)

            port.point = new_point
            moved_points[port.object_id] = new_point
          end
        end

        propagate_selected_port_movements!(
          network: network,
          selected_set: selected_set,
          moved_points: moved_points
        )
      rescue => error
        puts "SelectionResizeService.adjust_selected_layout_for_size_change! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def self.propagate_selected_port_movements!(network:, selected_set:, moved_points:)
        return if moved_points.empty?

        max_passes = 50
        pass = 0

        loop do
          pass += 1
          changed = false

          network.connections.each do |connection|
            port_a = connection.port_a
            port_b = connection.port_b

            next unless port_a && port_b
            next unless port_a.piece && port_b.piece

            next unless selected_set[port_a.piece.object_id]
            next unless selected_set[port_b.piece.object_id]

            a_moved = moved_points[port_a.object_id]
            b_moved = moved_points[port_b.object_id]

            if a_moved && !b_moved
              port_b.point = a_moved
              moved_points[port_b.object_id] = a_moved
              changed = true
            elsif b_moved && !a_moved
              port_a.point = b_moved
              moved_points[port_a.object_id] = b_moved
              changed = true
            elsif a_moved && b_moved && a_moved.distance(b_moved) > CONNECTION_TOLERANCE
              shared_midpoint = midpoint(a_moved, b_moved)
              next unless shared_midpoint

              port_a.point = shared_midpoint
              port_b.point = shared_midpoint

              moved_points[port_a.object_id] = shared_midpoint
              moved_points[port_b.object_id] = shared_midpoint

              changed = true
            end
          end

          break unless changed
          break if pass >= max_passes
        end
      rescue => error
        puts "SelectionResizeService.propagate_selected_port_movements! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def self.selected_boundary_connections(network, selected_pieces)
        selected_set = selected_pieces.each_with_object({}) do |piece, hash|
          hash[piece.object_id] = true
        end

        network.connections.select do |connection|
          piece_a = connection.port_a&.piece
          piece_b = connection.port_b&.piece

          next false unless piece_a && piece_b
          next false if piece_a == piece_b

          a_selected = selected_set[piece_a.object_id]
          b_selected = selected_set[piece_b.object_id]

          a_selected != b_selected
        end
      rescue
        []
      end

      def self.build_boundary_plan(boundary_connections:, selected_set:, target_dimensions:)
        boundary_connections.map do |connection|
          port_a = connection.port_a
          port_b = connection.port_b

          a_selected = selected_set[port_a.piece.object_id]
          b_selected = selected_set[port_b.piece.object_id]

          selected_port = a_selected ? port_a : port_b
          external_port = a_selected ? port_b : port_a

          external_dimensions = dimensions_for_port(external_port)
          reducer_length = Geometry::ReducerBuilder.default_length(
            external_dimensions,
            target_dimensions
          )

          {
            connection: connection,
            selected_port: selected_port,
            external_port: external_port,
            external_dimensions: external_dimensions,
            reducer_length: reducer_length
          }
        end
      rescue
        []
      end

      def self.apply_boundary_pullbacks!(boundary_plan)
        boundary_plan.each do |item|
          selected_port = item[:selected_port]
          external_port = item[:external_port]
          length = item[:reducer_length].to_f

          next unless selected_port && external_port
          next unless selected_port.point && external_port.point
          next if length <= EPSILON

          axis = boundary_reducer_axis(
            selected_port: selected_port,
            external_port: external_port
          )

          next unless axis
          next if axis.length <= EPSILON

          axis.normalize!

          # Anchor to the unselected duct. Put the selected port exactly one
          # reducer length away, along the axis from the unselected duct toward
          # the selected duct.
          selected_port.point = external_port.point.offset(axis, length)

          # Critical alignment fix:
          # The selected elbow/pipe port should face back toward the unselected
          # pipe/reducer. Without this, the rebuilt elbow can point at its old
          # tangent direction instead of the new boundary direction.
          selected_vector = axis.clone.reverse
          selected_vector.normalize! if selected_vector.length > EPSILON
          selected_port.vector = selected_vector
        end
      rescue => error
        puts "SelectionResizeService.apply_boundary_pullbacks! failed: #{error.message}"
        puts error.backtrace.join("\n")
      end

      def self.boundary_reducer_axis(selected_port:, external_port:)
        external_point = external_port.point
        selected_point = selected_port.point

        external_to_selected = external_point.vector_to(selected_point)

        if external_to_selected && external_to_selected.length > EPSILON
          external_to_selected.normalize!
        else
          external_to_selected = nil
        end

        candidates = []

        # Prefer the unselected duct's outward direction, because that is the
        # duct we are preserving. The reducer should usually be coaxial with it.
        if external_port.outward_vector && external_port.outward_vector.length > EPSILON
          axis = external_port.outward_vector.clone
          axis.normalize!

          if external_to_selected.nil? || axis.dot(external_to_selected) >= 0.0
            candidates << axis
          else
            candidates << axis.clone.reverse
          end
        end

        # Then try a direction from the current gap.
        candidates << external_to_selected if external_to_selected

        # Last fallback: use selected port direction, but reverse it so the axis
        # points from external duct toward selected duct.
        if selected_port.outward_vector && selected_port.outward_vector.length > EPSILON
          axis = selected_port.outward_vector.clone.reverse
          axis.normalize!

          if external_to_selected.nil? || axis.dot(external_to_selected) >= 0.0
            candidates << axis
          else
            candidates << axis.clone.reverse
          end
        end

        candidates.compact.find { |axis| axis.length > EPSILON }
      rescue => error
        puts "SelectionResizeService.boundary_reducer_axis failed: #{error.message}"
        nil
      end

      def self.insert_boundary_reducer!(
        model:,
        network:,
        selected_port:,
        external_port:,
        selected_dimensions:,
        external_dimensions:
      )
        return nil unless selected_port && external_port
        return nil unless selected_port.point && external_port.point

        remove_connection_between!(network, selected_port, external_port)

        remove_cap_for_port_if_possible(selected_port)
        remove_cap_for_port_if_possible(external_port)

        # Important direction fix:
        # Build the reducer from the unselected/external duct toward the resized
        # selected duct. This makes the reducer start where the old visual end was
        # and end at the newly repositioned selected port.
        start_point = external_port.point
        end_point = selected_port.point

        vector = start_point.vector_to(end_point)
        return nil if vector.length <= EPSILON

        vector.normalize!

        group = model.active_entities.add_group
        group.name =
          if selected_dimensions[:shape] == :rectangular
            "Auto Rectangular Duct Increaser / Reducer"
          else
            "Auto Round Duct Increaser / Reducer"
          end

        preferred_start_width_axis = external_port.width_axis || selected_port.width_axis
        preferred_start_height_axis = external_port.height_axis || selected_port.height_axis

        preferred_end_width_axis = selected_port.width_axis || external_port.width_axis
        preferred_end_height_axis = selected_port.height_axis || external_port.height_axis

        success = Geometry::ReducerBuilder.build_into(
          group,
          start_point,
          end_point,
          start_dimensions: external_dimensions,
          end_dimensions: selected_dimensions,
          preferred_width_axis: preferred_start_width_axis,
          preferred_height_axis: preferred_start_height_axis
        )

        unless success
          group.erase! if group.valid?
          return nil
        end

        start_basis =
          if external_dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              vector,
              preferred_width_axis: preferred_start_width_axis,
              preferred_height_axis: preferred_start_height_axis
            )
          else
            nil
          end

        end_basis =
          if selected_dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              vector,
              preferred_width_axis: preferred_end_width_axis,
              preferred_height_axis: preferred_end_height_axis
            )
          else
            nil
          end

        reducer_start_port = Model::Port.new(
          point: start_point,
          vector: vector.clone.reverse,
          diameter: external_dimensions[:diameter],
          shape: external_dimensions[:shape],
          width: external_dimensions[:width],
          height: external_dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        reducer_end_port = Model::Port.new(
          point: end_point,
          vector: vector,
          diameter: selected_dimensions[:diameter],
          shape: selected_dimensions[:shape],
          width: selected_dimensions[:width],
          height: selected_dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        reducer_piece = Model::DuctPiece.new(
          type: :reducer,
          group: group,
          ports: [reducer_start_port, reducer_end_port]
        )

        network.add_piece(reducer_piece)

        network.connect_ports(external_port, reducer_start_port)
        network.connect_ports(reducer_end_port, selected_port)

        PieceMetadataService.save_piece(reducer_piece)

        reducer_piece
      rescue => error
        puts "SelectionResizeService.insert_boundary_reducer! failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.remove_cap_for_port_if_possible(port)
        return unless port

        begin
          TeeInsertService.remove_cap_for_port(port)
          return
        rescue
          nil
        end

        begin
          TeeInsertService.send(:remove_cap_for_port, port)
          return
        rescue
          nil
        end
      rescue => error
        puts "SelectionResizeService.remove_cap_for_port_if_possible failed: #{error.message}"
      end

      def self.rebuild_selected_piece!(piece:, target_dimensions:)
        return false unless piece
        return false unless piece.group && piece.group.valid?

        case piece.type.to_sym
        when :pipe
          rebuild_pipe!(piece, target_dimensions)
        when :elbow
          rebuild_elbow!(piece, target_dimensions)
        when :reducer
          rebuild_reducer_as_same_size_piece!(piece, target_dimensions)
        else
          false
        end
      rescue => error
        puts "SelectionResizeService.rebuild_selected_piece! failed for #{piece&.type}: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_pipe!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]

        start_point = start_port.point
        end_point = end_port.point

        vector = start_point.vector_to(end_point)
        return false if vector.length <= EPSILON

        vector.normalize!

        erase_group_geometry(piece.group)

        success =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularPipeBuilder.build_into(
              piece.group,
              start_point,
              end_point,
              dimensions[:width],
              dimensions[:height],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: start_port.width_axis || end_port.width_axis,
              preferred_height_axis: start_port.height_axis || end_port.height_axis
            )
          else
            Geometry::PipeBuilder.build_into(
              piece.group,
              start_point,
              end_point,
              dimensions[:diameter],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false
            )
          end

        return false unless success

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: vector.clone.reverse,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        update_port_dimensions!(
          end_port,
          dimensions,
          direction: vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        true
      rescue => error
        puts "SelectionResizeService.rebuild_pipe! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_elbow!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]

        start_point = start_port.point
        end_point = end_port.point

        entry_vector = start_port.outward_vector.clone.reverse
        exit_vector = end_port.outward_vector.clone

        return false if entry_vector.length <= EPSILON
        return false if exit_vector.length <= EPSILON

        entry_vector.normalize!
        exit_vector.normalize!

        bend_radius = infer_bend_radius(
          start_point: start_point,
          end_point: end_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          dimensions: dimensions
        )

        return false unless bend_radius
        return false if bend_radius <= EPSILON

        erase_group_geometry(piece.group)

        success =
          if dimensions[:shape] == :rectangular
            build_rectangular_elbow_safely(
              group: piece.group,
              start_point: start_point,
              entry_vector: entry_vector,
              exit_vector: exit_vector,
              dimensions: dimensions,
              bend_radius: bend_radius,
              preferred_width_axis: start_port.width_axis || end_port.width_axis,
              preferred_height_axis: start_port.height_axis || end_port.height_axis
            )
          else
            build_round_elbow_safely(
              group: piece.group,
              start_point: start_point,
              entry_vector: entry_vector,
              exit_vector: exit_vector,
              dimensions: dimensions,
              bend_radius: bend_radius
            )
          end

        unless success
          puts "SelectionResizeService.rebuild_elbow! builder returned false."
          puts "  piece=#{piece.inspect}"
          puts "  shape=#{dimensions[:shape]}"
          puts "  diameter=#{dimensions[:diameter]}"
          puts "  width=#{dimensions[:width]}"
          puts "  height=#{dimensions[:height]}"
          puts "  bend_radius=#{bend_radius}"
          puts "  start_point=#{start_point}"
          puts "  end_point=#{end_point}"
          puts "  entry_vector=#{entry_vector}"
          puts "  exit_vector=#{exit_vector}"
          return false
        end

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: start_port.outward_vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        update_port_dimensions!(
          end_port,
          dimensions,
          direction: end_port.outward_vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        true
      rescue => error
        puts "SelectionResizeService.rebuild_elbow! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_round_elbow_safely(
        group:,
        start_point:,
        entry_vector:,
        exit_vector:,
        dimensions:,
        bend_radius:
      )
        Geometry::ElbowBuilder.build_into(
          group,
          start_point,
          entry_vector,
          exit_vector,
          dimensions[:diameter],
          bend_radius,
          cap_start: false,
          cap_end: false
        )
      rescue ArgumentError => error
        puts "SelectionResizeService.build_round_elbow_safely ArgumentError: #{error.message}"
        puts "This means ElbowBuilder.build_into signature does not match the resize service call."
        false
      rescue => error
        puts "SelectionResizeService.build_round_elbow_safely failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular_elbow_safely(
        group:,
        start_point:,
        entry_vector:,
        exit_vector:,
        dimensions:,
        bend_radius:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        Geometry::RectangularElbowBuilder.build_into(
          group,
          start_point,
          entry_vector,
          exit_vector,
          dimensions[:width],
          dimensions[:height],
          bend_radius,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      rescue ArgumentError => error
        puts "SelectionResizeService.build_rectangular_elbow_safely ArgumentError: #{error.message}"
        puts "This means RectangularElbowBuilder.build_into signature does not match the resize service call."
        false
      rescue => error
        puts "SelectionResizeService.build_rectangular_elbow_safely failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.rebuild_reducer_as_same_size_piece!(piece, dimensions)
        ports = Array(piece.ports)
        return false unless ports.length >= 2

        start_port = ports[0]
        end_port = ports[1]

        start_point = start_port.point
        end_point = end_port.point

        vector = start_point.vector_to(end_point)
        return false if vector.length <= EPSILON

        vector.normalize!

        erase_group_geometry(piece.group)

        success = Geometry::ReducerBuilder.build_into(
          piece.group,
          start_point,
          end_point,
          start_dimensions: dimensions,
          end_dimensions: dimensions,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        return false unless success

        update_port_dimensions!(
          start_port,
          dimensions,
          direction: vector.clone.reverse,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        update_port_dimensions!(
          end_port,
          dimensions,
          direction: vector,
          preferred_width_axis: start_port.width_axis || end_port.width_axis,
          preferred_height_axis: start_port.height_axis || end_port.height_axis
        )

        true
      rescue => error
        puts "SelectionResizeService.rebuild_reducer_as_same_size_piece! failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.infer_bend_radius(start_point:, end_point:, entry_vector:, exit_vector:, dimensions:)
        angle = entry_vector.angle_between(exit_vector)
        return nil if angle <= EPSILON
        return nil if angle >= Math::PI - EPSILON

        chord = start_point.distance(end_point)
        radius = chord / (2.0 * Math.sin(angle / 2.0))

        min_radius =
          if dimensions[:shape] == :rectangular
            [dimensions[:width], dimensions[:height]].max * 0.75
          else
            dimensions[:diameter] * 0.75
          end

        [radius, min_radius].max
      rescue
        nil
      end

      def self.update_port_dimensions!(
        port,
        dimensions,
        direction:,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        port.shape = dimensions[:shape]
        port.diameter = dimensions[:diameter]
        port.width = dimensions[:width]
        port.height = dimensions[:height]

        vector = direction.clone
        vector.normalize! if vector.length > EPSILON
        port.vector = vector

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(
            vector,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )

          if basis
            port.width_axis = basis[:width_axis]
            port.height_axis = basis[:height_axis]
          end
        else
          port.width_axis = nil
          port.height_axis = nil
        end

        port
      rescue => error
        puts "SelectionResizeService.update_port_dimensions! failed: #{error.message}"
        port
      end

      def self.dimensions_for_piece(piece)
        port = Array(piece.ports).compact.first
        dimensions_for_port(port)
      rescue
        nil
      end

      def self.dimensions_for_port(port)
        Model::Port.dimensions_from_params({}, port)
      rescue
        {
          shape: :round,
          diameter: 8.0,
          width: 8.0,
          height: 8.0
        }
      end

      def self.largest_size(dimensions)
        return 0.0 unless dimensions

        [
          dimensions[:diameter],
          dimensions[:width],
          dimensions[:height]
        ].compact.map(&:to_f).max.to_f
      rescue
        0.0
      end

      def self.remove_connection_between!(network, port_a, port_b)
        network.connections.delete_if do |connection|
          (connection.port_a == port_a && connection.port_b == port_b) ||
            (connection.port_a == port_b && connection.port_b == port_a)
        end
      rescue => error
        puts "SelectionResizeService.remove_connection_between! failed: #{error.message}"
      end

      def self.erase_group_geometry(group)
        return unless group && group.valid?

        entities = group.entities

        begin
          entities.clear!
          return
        rescue
          nil
        end

        entities.to_a.reverse_each do |entity|
          begin
            entity.erase! if entity && entity.valid?
          rescue
            nil
          end
        end
      rescue => error
        puts "SelectionResizeService.erase_group_geometry failed: #{error.message}"
      end

      def self.midpoint(point_a, point_b)
        Geom::Point3d.new(
          (point_a.x + point_b.x) / 2.0,
          (point_a.y + point_b.y) / 2.0,
          (point_a.z + point_b.z) / 2.0
        )
      rescue
        nil
      end

      def self.positive_number(value, fallback)
        number = value.to_f
        number > 0.0 ? number : fallback
      rescue
        fallback
      end
    end
  end
end
