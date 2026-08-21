# ===== Consolidated from: tool/duct_tool_vents.rb =====
module DuctExtension
  module Tool
    module DuctToolVents
      private

      def handle_vent_click(view, x, y, clicked_point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        pipe_piece ||= nearest_pipe_piece_for_vent_click(clicked_point)

        unless pipe_piece
          ::UI.messagebox("Add Vent mode: click an existing duct pipe. Click near the end for an end cover, or click the side for a register.")
          return
        end

        unless pipe_piece.ports && pipe_piece.ports.length >= 2
          ::UI.messagebox("Add Vent mode: vents can be placed on duct pipes.")
          return
        end

        dimensions = Model::Port.dimensions_from_params({}, pipe_piece.ports.first)
        adopt_catalog_target_dimensions!(pipe_piece.ports.first)

        # Catalog components carry their own connector/opening dimensions. The
        # old generic vent-size dialog only affected generic geometry and was
        # confusing in strict catalog mode, so skip it entirely there.
        input =
          if Catalog::Manager.active?(Sketchup.active_model)
            {
              register_width: nil,
              register_height: nil,
              register_bumped_out: true,
              cover_diameter: nil,
              cover_width: nil,
              cover_height: nil
            }
          else
            prompt_for_vent(dimensions)
          end
        return unless input

        result = Services::VentInsertService.insert_on_piece(
          model: Sketchup.active_model,
          network: @network,
          duct_piece: pipe_piece,
          click_point: clicked_point,
          register_width: input[:register_width],
          register_height: input[:register_height],
          register_bumped_out: input[:register_bumped_out],
          cover_diameter: input[:cover_diameter],
          cover_width: input[:cover_width],
          cover_height: input[:cover_height],
          repeat_enabled: duct_tool_class_setting(:@@vent_repeat_enabled),
          repeat_direction: duct_tool_class_setting(:@@vent_repeat_direction),
          repeat_interval: duct_tool_class_setting(:@@vent_repeat_interval),
          view: view
        )

        if result
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          @fitting_mode = :vent

          if result[:vent_type] == :side_register_repeat
            Sketchup.status_text = "#{result[:count]} vents inserted. Still in Add Vent mode."
          else
            Sketchup.status_text = "Vent inserted. Still in Add Vent mode: click another pipe end or side."
          end
        else
          ::UI.messagebox("Could not insert vent here. Try clicking closer to the side or end of a duct pipe.")
        end
      rescue => error
        puts "DuctTool.handle_vent_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert vent. Check the Ruby Console for details.")
      end

      def nearest_pipe_piece_for_vent_click(clicked_point)
        return nil unless @network && @network.respond_to?(:pieces)

        best_piece = nil
        best_distance = nil

        @network.pieces.each do |piece|
          next unless piece
          next unless piece.type == :pipe
          next unless piece.group && piece.group.valid?
          next unless piece.ports && piece.ports.length >= 2

          port_a = piece.ports[0]
          port_b = piece.ports[1]
          next unless port_a && port_b && port_a.point && port_b.point

          closest = closest_point_on_segment_for_vent(
            port_a.point,
            port_b.point,
            clicked_point
          )
          next unless closest

          distance = closest.distance(clicked_point)
          dimensions = Model::Port.dimensions_from_params({}, port_a)

          tolerance = [
            dimensions[:diameter].to_f,
            dimensions[:width].to_f,
            dimensions[:height].to_f,
            6.0
          ].max * 1.8

          next if distance > tolerance

          if best_distance.nil? || distance < best_distance
            best_distance = distance
            best_piece = piece
          end
        end

        best_piece
      rescue => error
        puts "DuctTool.nearest_pipe_piece_for_vent_click failed: #{error.message}"
        nil
      end

      def closest_point_on_segment_for_vent(start_point, end_point, point)
        axis = start_point.vector_to(end_point)
        return nil if axis.length <= 0.0

        length = axis.length
        axis.normalize!

        amount = start_point.vector_to(point).dot(axis)
        amount = [[amount, 0.0].max, length].min

        start_point.offset(axis, amount)
      rescue
        nil
      end

      def prompt_for_vent(dimensions)
        dimensions[:shape] == :rectangular ? prompt_for_rectangular_vent(dimensions) : prompt_for_round_vent(dimensions)
      end

      def prompt_for_round_vent(dimensions)
        diameter = dimensions[:diameter].to_f

        input = ::UI.inputbox(
          [
            "Side Register Plate Width:",
            "Side Register Plate Height:",
            "Register Bumped Out?",
            "End Cover Diameter:"
          ],
          [
            InputHelpers.format_number(diameter * 1.35),
            InputHelpers.format_number(diameter * 0.55),
            "Yes",
            InputHelpers.format_number(diameter * 1.22)
          ],
          ["", "", "Yes|No", ""],
          "Round Duct Vent"
        )

        return nil unless input

        {
          register_width: InputHelpers.positive_number(input[0], diameter * 1.35),
          register_height: InputHelpers.positive_number(input[1], diameter * 0.55),
          register_bumped_out: InputHelpers.yes?(input[2]),
          cover_diameter: InputHelpers.positive_number(input[3], diameter * 1.22),
          cover_width: nil,
          cover_height: nil
        }
      end

      def prompt_for_rectangular_vent(dimensions)
        width = dimensions[:width].to_f
        height = dimensions[:height].to_f
        largest = [width, height].max

        input = ::UI.inputbox(
          [
            "Side Register Plate Width:",
            "Side Register Plate Height:",
            "Register Bumped Out?",
            "End Cover Width:",
            "End Cover Height:"
          ],
          [
            InputHelpers.format_number(largest * 1.10),
            InputHelpers.format_number(largest * 0.45),
            "Yes",
            InputHelpers.format_number(width * 1.22),
            InputHelpers.format_number(height * 1.22)
          ],
          ["", "", "Yes|No", "", ""],
          "Rectangular Duct Vent"
        )

        return nil unless input

        {
          register_width: InputHelpers.positive_number(input[0], largest * 1.10),
          register_height: InputHelpers.positive_number(input[1], largest * 0.45),
          register_bumped_out: InputHelpers.yes?(input[2]),
          cover_diameter: nil,
          cover_width: InputHelpers.positive_number(input[3], width * 1.22),
          cover_height: InputHelpers.positive_number(input[4], height * 1.22)
        }
      end

    end
  end
end

# ===== Consolidated from: tool/duct_tool_fittings.rb =====
module DuctExtension
  module Tool
    module DuctToolFittings
      SPECIAL_FITTING_CLICK_HANDLERS = {
        end_tee: :handle_end_tee_click,
        end_cross: :handle_end_cross_click,
        end_wye: :handle_end_wye_click,
        end_reducer: :handle_end_reducer_click,
        tee: :handle_manual_tee_click,
        wye_saddle: :handle_manual_wye_saddle_click
      }.freeze

      END_BRANCH_FITTINGS = {
        tee: {
          label: "End Tee",
          service: DuctExtension::Services::EndTeeInsertService,
          side_selector: :choose_branch_direction_for_end_tee,
          success: "End tee inserted. Click either open tee end to continue.",
          failure: "Could not insert end tee here."
        },
        cross: {
          label: "End Cross",
          service: DuctExtension::Services::EndCrossInsertService,
          side_selector: :choose_branch_direction_for_end_tee,
          success: "End cross inserted. Click any open cross end to continue.",
          failure: "Could not insert end cross here."
        },
        wye: {
          label: "End Wye",
          service: DuctExtension::Services::EndWyeInsertService,
          side_selector: :choose_branch_direction_for_end_wye,
          success: "End wye inserted. Click either open wye end to continue.",
          failure: "Could not insert end wye here."
        }
      }.freeze

      private

      def dispatch_special_fitting_click(view, x, y, clicked_point)
        handler = SPECIAL_FITTING_CLICK_HANDLERS[@fitting_mode]
        return false unless handler

        send(handler, view, x, y, clicked_point)
        true
      end

      def begin_connector_swing_drag(view, x, y)
        result = Services::ConnectorSwingService.begin_drag(
          model: Sketchup.active_model,
          network: @network,
          view: view,
          x: x,
          y: y
        )

        case result[:status]
        when :ok
          @connector_swing_session = result[:session]
          @last_port = nil
          @start_point = nil
          @orthogonal_axis_lock = nil
          Sketchup.status_text =
            "Ctrl-drag to swing connector. Angle snaps every #{Services::ConnectorSwingService::DRAG_SNAP_DEGREES} degrees."
          true
        when :no_piece
          Sketchup.status_text = "Ctrl-drag a tee, cross, or wye to swing it."
          false
        when :too_many_connections
          ::UI.messagebox(
            "This connector has too many attached ducts to swing safely.\n\n" \
            "Disconnect the side branch first, then Ctrl-drag the connector again."
          )
          false
        when :not_swingable
          Sketchup.status_text = "Only tees, crosses, and wyes can be swung right now."
          false
        else
          ::UI.messagebox("Could not start connector swing. Check the Ruby Console for details.")
          false
        end
      rescue => error
        puts "DuctTool.begin_connector_swing_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        @connector_swing_session = nil
        ::UI.messagebox("Could not start connector swing. Check the Ruby Console for details.")
        false
      end

      def update_connector_swing_drag(view, x, y)
        return false unless @connector_swing_session

        result = Services::ConnectorSwingService.update_drag(
          session: @connector_swing_session,
          view: view,
          x: x,
          y: y
        )

        if result[:status] == :ok
          Sketchup.status_text =
            "Connector swing: #{result[:angle_degrees]} degrees (#{Services::ConnectorSwingService::DRAG_SNAP_DEGREES}-degree snap)."
          view.invalidate if view
          true
        else
          @connector_swing_session = nil
          ::UI.messagebox("Could not continue connector swing. The change was rolled back.")
          false
        end
      rescue => error
        puts "DuctTool.update_connector_swing_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        cancel_connector_swing_drag
        false
      end

      def finish_connector_swing_drag(view = nil)
        return false unless @connector_swing_session

        session = @connector_swing_session
        @connector_swing_session = nil

        result = Services::ConnectorSwingService.finish_drag(session, legacy_click: true)

        if result[:status] == :ok
          @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
          Sketchup.status_text = "Connector swung to #{result[:angle_degrees]} degrees."
          view.invalidate if view
          true
        else
          ::UI.messagebox("Could not finish connector swing. The change was rolled back.")
          false
        end
      rescue => error
        puts "DuctTool.finish_connector_swing_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        Services::ConnectorSwingService.cancel_drag(session) if defined?(session) && session
        false
      end

      def cancel_connector_swing_drag(view = nil)
        session = @connector_swing_session
        @connector_swing_session = nil
        return false unless session

        Services::ConnectorSwingService.cancel_drag(session)
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        update_status_for_current_shape
        view.invalidate if view
        true
      rescue => error
        puts "DuctTool.cancel_connector_swing_drag failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      # Kept for code that still calls the old one-click helper directly.
      def handle_connector_swing_click(view, x, y)
        return unless begin_connector_swing_drag(view, x, y)

        finish_connector_swing_drag(view)
      end

      def handle_end_tee_click(view, x, y, point)
        handle_end_branch_fitting_click(:tee, view, x, y, point)
      end

      def handle_end_cross_click(view, x, y, point)
        handle_end_branch_fitting_click(:cross, view, x, y, point)
      end

      def handle_end_wye_click(view, x, y, point)
        handle_end_branch_fitting_click(:wye, view, x, y, point)
      end

      def handle_end_branch_fitting_click(type, view, x, y, point)
        config = END_BRANCH_FITTINGS[type]
        return unless config

        snapped_port = open_port_at_click(view, x, y, point)

        unless snapped_port
          ::UI.messagebox("#{config[:label]} mode: click an open end port.")
          return
        end

        adopt_catalog_target_dimensions!(snapped_port)
        side_vector = send(config[:side_selector], snapped_port)
        result = config[:service].insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          side_vector: side_vector
        )

        unless result
          ::UI.messagebox(config[:failure])
          return
        end

        reset_after_end_component(snapped_port)
        Sketchup.status_text = config[:success]
      rescue => error
        puts "DuctTool.handle_end_branch_fitting_click failed for #{type}: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert #{type} here. Check the Ruby Console for details.")
      end

      def open_port_at_click(view, x, y, point)
        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: point
        )
        snap&.port
      end

      def reset_after_end_component(dimension_port = nil)
        @last_port = nil
        @start_point = nil
        @orthogonal_axis_lock = nil
        copy_dimensions_from_port(dimension_port) if dimension_port
        @fitting_mode = :elbow
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
      end

      def handle_end_reducer_click(view, x, y, point)
        snapped_port = open_port_at_click(view, x, y, point)

        unless snapped_port
          ::UI.messagebox("End Increaser / Reducer mode: click an open end port.")
          return
        end

        adopt_catalog_target_dimensions!(snapped_port)
        input = prompt_for_reducer_size(snapped_port)
        return unless input

        result = Services::EndReducerInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: snapped_port,
          new_shape: input[:shape],
          new_diameter: input[:diameter],
          new_width: input[:width],
          new_height: input[:height],
          length: input[:length]
        )

        unless result
          ::UI.messagebox("Could not insert increaser / reducer here.")
          return
        end

        reset_after_end_component(result[:new_port])
        Sketchup.status_text = "Increaser / reducer inserted. Click the new open end to continue."
      rescue => error
        puts "DuctTool.handle_end_reducer_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not insert increaser / reducer. Check the Ruby Console for details.")
      end

      def handle_manual_tee_click(view, x, y, point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        unless pipe_piece
          ::UI.messagebox("Add Tee mode: click an existing duct pipe.")
          return
        end

        dimensions =
          if pipe_piece.ports && pipe_piece.ports[0]
            Model::Port.dimensions_from_params({}, pipe_piece.ports[0])
          else
            { shape: @duct_shape }
          end

        adopt_catalog_target_dimensions!(pipe_piece.ports[0]) if pipe_piece.ports && pipe_piece.ports[0]

        branch_direction =
          if dimensions[:shape] == :rectangular
            choose_branch_direction_from_click(pipe_piece, point)
          else
            choose_round_tee_branch_direction(pipe_piece, point, view)
          end

        requested_branch_dimensions =
          if Catalog::Manager.active?(Sketchup.active_model)
            # Catalog inline tee saddles have a fixed native branch connector.
            # Keep that connector truthful instead of immediately inventing a
            # transition to whatever size happens to be selected in the tool.
            nil
          else
            {
              shape: @duct_shape,
              diameter: @current_diameter,
              width: @current_width,
              height: @current_height
            }
          end

        result = Services::TeeInsertService.insert_tee_on_pipe(
          model: Sketchup.active_model,
          network: @network,
          pipe_piece: pipe_piece,
          tap_point: point,
          branch_direction: branch_direction,
          branch_dimensions: requested_branch_dimensions
        )

        unless result
          ::UI.messagebox("Could not insert tee here. Try clicking farther from the pipe ends.")
          return
        end

        @last_port = result[:branch_port]
        @start_point = nil
        @orthogonal_axis_lock = nil
        copy_dimensions_from_port(@last_port)
        @fitting_mode = :elbow

        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

        Sketchup.status_text = "Tee inserted. Click next orthogonal point to draw branch."
      end

      def handle_manual_wye_saddle_click(view, x, y, point)
        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        unless pipe_piece
          ::UI.messagebox("Add Wye Saddle mode: click an existing round duct pipe.")
          return
        end

        dimensions = Model::Port.dimensions_from_params({}, pipe_piece.ports[0])
        adopt_catalog_target_dimensions!(pipe_piece.ports[0])
        unless dimensions[:shape] == :round
          ::UI.messagebox("Master Flow 45YS4 is a round-pipe saddle. Click an existing round duct pipe.")
          return
        end

        side_direction = choose_round_tee_branch_direction(pipe_piece, point, view)
        lean = ::UI.inputbox(
          ["45-degree branch lean:"],
          ["Along pipe direction"],
          ["Along pipe direction|Against pipe direction"],
          "Master Flow 45YS4 Wye Saddle"
        )
        return unless lean
        forward_sign = lean[0].to_s == "Against pipe direction" ? -1.0 : 1.0

        result = Services::InlineWyeInsertService.insert_wye_on_pipe(
          model: Sketchup.active_model,
          network: @network,
          pipe_piece: pipe_piece,
          tap_point: point,
          side_direction: side_direction,
          forward_sign: forward_sign,
          # 45YS4 has a fixed 4-inch branch connector. Start the branch at
          # that native size; a real catalog reducer can be added afterward.
          branch_dimensions: nil
        )

        unless result
          ::UI.messagebox("Could not insert the catalog wye saddle here. Check main size and distance from the pipe ends.")
          return
        end

        @last_port = result[:branch_port]
        @start_point = nil
        @orthogonal_axis_lock = nil
        copy_dimensions_from_port(@last_port)
        @fitting_mode = :elbow
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        Sketchup.status_text = "45-degree wye saddle inserted. Click the next point to continue the branch."
      rescue => error
        puts "DuctTool.handle_manual_wye_saddle_click failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        ::UI.messagebox("Could not insert wye saddle. Check the Ruby Console for details.")
      end

      # In catalog mode, component availability follows the semantic duct that
      # was actually clicked, not whatever size happened to be selected earlier.
      # This keeps subsequent prompts/status aligned when jumping between, for
      # example, a rectangular trunk and a 6-inch round branch.
      # When a new catalog run is started from an existing open port, preserve
      # the duct size/product the user selected for the new run. If that differs
      # from the clicked port, insert the real stocked reducer/increaser/adapter
      # automatically when the active catalog contains one.
      #
      # Return values:
      #   :same        - no transition is needed
      #   :inserted    - a catalog transition was inserted and @last_port moved
      #   :unsupported - sizes differ but the catalog has no matching transition
      #   :failed      - a matching product exists but insertion failed
      def auto_catalog_transition_from_start_port!(stem_port)
        return :same unless stem_port
        return :same unless Catalog::Manager.active?(Sketchup.active_model)

        source_dimensions = Model::Port.dimensions_from_params({}, stem_port)
        target_dimensions = {
          shape: @duct_shape,
          diameter: @current_diameter,
          width: @current_width,
          height: @current_height
        }

        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)
        return :same if source.shape == target.shape && source.same_size?(target, tolerance: Catalog::Manager::TOLERANCE)

        product = Catalog::Manager.transition_product(source_dimensions, target_dimensions, Sketchup.active_model)
        unless product
          # The click path removes temporary open-port caps before arriving here.
          # Restore the cap because no connection was actually made.
          Services::PortCapService.add(stem_port.piece.group, stem_port) if stem_port.piece && stem_port.piece.group
          ::UI.messagebox(
            "The selected catalog duct (#{Catalog::Manager.dimensions_label(target_dimensions)}) cannot start from " \
            "this #{Catalog::Manager.dimensions_label(source_dimensions)} port because the loaded catalog has no matching reducer/increaser or converter.\n\n" \
            "Choose a compatible catalog duct size, or start the run somewhere else."
          )
          return :unsupported
        end

        fallback_length = Geometry::ReducerBuilder.default_length(source_dimensions, target_dimensions)
        length = Catalog::Manager.transition_length(product, fallback_length)

        result = Services::EndReducerInsertService.insert_at_port(
          model: Sketchup.active_model,
          network: @network,
          stem_port: stem_port,
          new_shape: target.shape,
          new_diameter: target.round? ? target.diameter : nil,
          new_width: target.rectangular? ? target.width : nil,
          new_height: target.rectangular? ? target.height : nil,
          length: length
        )

        unless result && result[:new_port]
          Services::PortCapService.add(stem_port.piece.group, stem_port) if stem_port.piece && stem_port.piece.group
          return :failed
        end

        @last_port = result[:new_port]
        @start_point = nil
        @orthogonal_axis_lock = nil
        reset_typed_length
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)

        Sketchup.status_text =
          "Inserted Master Flow #{product.sku} automatically. Click the next point to continue with #{Catalog::Manager.dimensions_label(target_dimensions)} duct."
        :inserted
      rescue => error
        puts "DuctTool.auto_catalog_transition_from_start_port! failed: #{error.message}"
        puts error.backtrace.join("\n")
        :failed
      end

      def adopt_catalog_target_dimensions!(port)
        return false unless port
        return false unless Catalog::Manager.active?(Sketchup.active_model)

        copy_dimensions_from_port(port)
        set_duct_tool_class_setting(:@@last_duct_shape, @duct_shape)
        set_duct_tool_class_setting(:@@last_diameter, @current_diameter)
        set_duct_tool_class_setting(:@@last_width, @current_width)
        set_duct_tool_class_setting(:@@last_height, @current_height)
        true
      rescue => error
        puts "DuctTool.adopt_catalog_target_dimensions failed: #{error.message}"
        false
      end

      def try_auto_tee_target(view, x, y, clicked_point)
        return nil unless @last_port || @start_point

        pipe_piece = Services::SnapService.picked_pipe_piece(
          network: @network,
          view: view,
          x: x,
          y: y
        )

        return nil unless pipe_piece

        start = active_route_start_point
        return nil unless start

        requested_branch_direction =
          if @last_port && @last_port.respond_to?(:outward_vector)
            @last_port.outward_vector
          else
            start.vector_to(clicked_point)
          end

        Services::PipeTargetConnectionService.insert_smart_tee_target(
          model: Sketchup.active_model,
          network: @network,
          target_pipe_piece: pipe_piece,
          click_point: clicked_point,
          active_start_point: start,
          active_start_port: @last_port,
          active_dimensions: {
            shape: @duct_shape,
            diameter: @current_diameter,
            width: @current_width,
            height: @current_height
          },
          requested_branch_direction: requested_branch_direction
        )
      end

      def choose_round_tee_branch_direction(pipe_piece, click_point, view)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return choose_branch_direction(pipe_piece) if main_vector.length == 0

        main_vector.normalize!

        requested =
          case @round_tee_side_mode
          when :positive_z
            Geom::Vector3d.new(0, 0, 1)
          when :negative_z
            Geom::Vector3d.new(0, 0, -1)
          when :positive_x
            Geom::Vector3d.new(1, 0, 0)
          when :negative_x
            Geom::Vector3d.new(-1, 0, 0)
          when :positive_y
            Geom::Vector3d.new(0, 1, 0)
          when :negative_y
            Geom::Vector3d.new(0, -1, 0)
          when :toward_camera
            camera_direction = view && view.camera ? view.camera.direction : nil
            camera_direction ? camera_direction.clone.reverse : nil
          when :away_from_camera
            camera_direction = view && view.camera ? view.camera.direction : nil
            camera_direction ? camera_direction.clone : nil
          else
            return choose_branch_direction_from_click(pipe_piece, click_point)
          end

        side = perpendicularized_to_axis(requested, main_vector)

        side || choose_branch_direction_from_click(pipe_piece, click_point)
      end

      def choose_branch_direction(pipe_piece)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return Geom::Vector3d.new(1, 0, 0) if main_vector.length == 0

        main_vector.normalize!

        z_axis = Geom::Vector3d.new(0, 0, 1)
        branch = main_vector.cross(z_axis)

        if branch.length == 0
          branch = main_vector.cross(Geom::Vector3d.new(1, 0, 0))
        end

        branch.normalize!
        branch
      end

      def choose_branch_direction_from_click(pipe_piece, click_point)
        main_vector = pipe_piece.ports[0].point.vector_to(pipe_piece.ports[1].point)
        return choose_branch_direction(pipe_piece) if main_vector.length == 0

        main_vector.normalize!

        pipe_start = pipe_piece.ports[0].point
        from_start = pipe_start.vector_to(click_point)
        distance_along = from_start.dot(main_vector)
        closest_on_pipe = pipe_start.offset(main_vector, distance_along)

        side_vector = closest_on_pipe.vector_to(click_point)
        return choose_branch_direction(pipe_piece) if side_vector.length == 0

        side_vector = perpendicularized_to_axis(side_vector, main_vector)
        side_vector || choose_branch_direction(pipe_piece)
      end

      def choose_branch_direction_for_end_tee(stem_port)
        stem = stem_port.outward_vector.clone
        return Geom::Vector3d.new(1, 0, 0) if stem.length == 0
        stem.normalize!

        preferred = stem.cross(Geom::Vector3d.new(0, 0, 1))
        preferred = stem.cross(Geom::Vector3d.new(1, 0, 0)) if preferred.length == 0
        preferred.normalize!

        # A rectangular end fitting should grow along one of the existing face
        # axes, not an arbitrary world-space perpendicular. That preserves roll
        # and keeps the tee/crossbar square to the incoming duct.
        if stem_port.respond_to?(:rectangular?) && stem_port.rectangular?
          # Keep the tee crossbar on the incoming duct's width axis. Using the
          # height axis here swaps rectangular width/height at the stem socket
          # and is the main cause of rolled/twisted end tees on angled runs.
          width_axis = perpendicularized_to_axis(stem_port.width_axis, stem)
          if width_axis
            opposite = width_axis.clone.reverse
            return (width_axis.dot(preferred) >= opposite.dot(preferred) ? width_axis : opposite)
          end
        end

        preferred
      end

      def choose_branch_direction_for_end_wye(stem_port)
        # Reuse the same side-selection basis as end tees/crosses. The actual
        # wye branch angle is created inside WyeBuilder, so this side vector only
        # decides which side the 45-degree branch leans toward.
        choose_branch_direction_for_end_tee(stem_port)
      end

      def perpendicularized_to_axis(vector, axis)
        Geometry::VectorMath.perpendicularized(vector, axis)
      end

    end
  end
end

