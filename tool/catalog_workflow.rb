module DuctExtension
  module Tool
    # Catalog-mode placement deliberately does not use the base automatic route
    # planner. A stocked fitting is a rigid object: after a straight run the next
    # click places the selected elbow, and only the following click establishes
    # the length of the next straight run. This keeps the base/free-form workflow
    # untouched while making catalog construction behave like assembling parts.
    module DuctToolCatalogWorkflow
      CATALOG_DIRECTION_DOT = 0.985
      CATALOG_MIN_RUN_LENGTH = 0.05

      private

      def catalog_workflow_active?
        Catalog::Manager.active?(Sketchup.active_model) && @fitting_mode == :elbow
      rescue
        false
      end

      def reset_catalog_workflow!
        @catalog_phase = :start
      end

      def catalog_phase
        return @catalog_phase if @catalog_phase
        return :elbow if @last_port
        return :run if @start_point

        :start
      end

      def handle_catalog_build_click(view, x, y, clicked_point)
        return false unless catalog_workflow_active?
        return true unless clicked_point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: clicked_point
        )
        snapped_port = snap&.port

        # Nothing is active yet. Clicking empty space establishes the beginning
        # of the first straight run. Clicking an existing open port establishes
        # an inlet from which the next action is a catalog elbow.
        unless @last_port || @start_point
          if snapped_port
            @last_port = snapped_port
            @start_point = nil
            copy_dimensions_from_port(snapped_port)
            @catalog_phase = catalog_phase_for_snapped_port(snapped_port)
            @orthogonal_axis_lock = nil
            reset_typed_length
            update_catalog_status
          else
            @start_point = clicked_point
            @last_port = nil
            @catalog_phase = :run
            @orthogonal_axis_lock = nil
            reset_typed_length
            update_catalog_status
          end
          return true
        end

        if catalog_phase == :elbow
          return place_catalog_elbow(view, x, y, clicked_point)
        end

        place_catalog_straight_run(view, x, y, clicked_point, snapped_port: snapped_port)
      rescue => error
        puts "DuctToolCatalogWorkflow.handle_catalog_build_click failed: #{error.message}"
        puts error.backtrace.join("\n")
        ::UI.messagebox("Could not place the catalog component. Check the Ruby Console for details.") rescue nil
        true
      end

      def place_catalog_elbow(view, x, y, clicked_point)
        unless @last_port
          Sketchup.status_text = "A catalog elbow needs an open duct port. Place a straight run first."
          return true
        end

        dimensions = Model::Port.dimensions_from_params({}, @last_port)
        raw_point = click_route_point(view, x, y, @last_port.point, clicked_point)
        selection = catalog_connection_choice(@last_port, raw_point)

        # A forward click means "no fitting here". It advances to the run-length
        # phase while keeping the same open port. This makes straight continuation
        # possible without weakening the elbow-first catalog workflow.
        if selection == :straight
          @catalog_phase = :run
          @start_point = nil
          @orthogonal_axis_lock = nil
          reset_typed_length
          Sketchup.status_text = "Straight continuation selected. Click ahead to set the next catalog run length."
          view.invalidate if view
          return true
        end

        product = Catalog::Manager.preferred_elbow(Sketchup.active_model, dimensions)
        unless product
          ::UI.messagebox(
            "Master Flow has no elbow for #{Catalog::Manager.dimensions_label(dimensions)}.\n\n" \
            "Click forward from the open end to continue straight, or choose a catalog transition to a size that has an elbow."
          )
          return true
        end

        exit_vector = catalog_elbow_exit_direction(@last_port, raw_point, product)
        unless exit_vector
          Sketchup.status_text = catalog_elbow_direction_error(@last_port, product)
          return true
        end

        entry_vector = normalized_vector(@last_port.outward_vector)
        return true unless entry_vector

        bend_radius = Catalog::Manager.elbow_bend_radius(
          product,
          dimensions,
          Model::DuctDimensions.coerce(dimensions).largest
        )

        step = Model::BuildStep.new(
          :elbow,
          Model::DuctDimensions.coerce(dimensions).to_h.merge(
            source_port: @last_port,
            start_point: @last_port.point,
            entry_vector: entry_vector,
            exit_vector: exit_vector,
            bend_radius: bend_radius
          )
        )

        Services::PortCapService.remove(@last_port)
        result = Services::GeometryExecutor.execute(
          Sketchup.active_model,
          [step],
          @network
        )

        unless result
          Services::PortCapService.add(@last_port) rescue nil
          return true
        end

        @last_port = result[:last_port]
        @start_point = nil
        copy_dimensions_from_port(@last_port)
        @catalog_phase = :run
        @orthogonal_axis_lock = nil
        reset_typed_length
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        update_catalog_status
        true
      rescue => error
        puts "DuctToolCatalogWorkflow.place_catalog_elbow failed: #{error.message}"
        puts error.backtrace.join("\n")
        true
      end

      def place_catalog_straight_run(view, x, y, clicked_point, snapped_port: nil, typed_length: nil)
        start_point = active_route_start_point
        return true unless start_point

        # A catalog run may connect directly into another open port, including
        # through a real catalog reducer/stack boot. Straight-only here is
        # intentional: if the target is around a corner, the user must place a
        # stocked elbow first instead of invoking the base auto-router.
        if snapped_port && snapped_port != @last_port && !typed_length
          result = Services::PortToPortRouteService.connect(
            model: Sketchup.active_model,
            network: @network,
            source_port: @last_port,
            source_point: @start_point,
            target_port: snapped_port,
            diameter: @current_diameter,
            shape: @duct_shape,
            width: @current_width,
            height: @current_height,
            fitting_mode: :straight
          )

          if result
            @last_port = nil
            @start_point = nil
            @catalog_phase = :start
            @orthogonal_axis_lock = nil
            reset_typed_length
            @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
            Sketchup.status_text = "Catalog connection complete. Click to begin another straight run."
          else
            ::UI.messagebox(
              "That catalog connection is not a straight continuation.\n\n" \
              "Place the selected elbow first, then draw the straight run from its fixed outlet."
            )
          end
          return true
        end

        raw_point = click_route_point(view, x, y, start_point, clicked_point)
        end_point = catalog_run_end_point(start_point, raw_point, typed_length: typed_length)
        unless end_point && start_point.distance(end_point) >= CATALOG_MIN_RUN_LENGTH
          Sketchup.status_text = catalog_phase == :run && @last_port ?
            "Catalog run must extend forward from the current fitting outlet." :
            "Move farther from the start point to place the catalog straight run."
          return true
        end

        dimensions = current_dimensions
        params = dimensions.to_h.merge(
          start_point: start_point,
          end_point: end_point
        )
        params[:source_port] = @last_port if @last_port

        Services::PortCapService.remove(@last_port) if @last_port
        result = Services::GeometryExecutor.execute(
          Sketchup.active_model,
          [Model::BuildStep.new(:pipe, params)],
          @network
        )

        unless result
          Services::PortCapService.add(@last_port) if @last_port rescue nil
          return true
        end

        @last_port = result[:last_port]
        @start_point = nil
        copy_dimensions_from_port(@last_port)
        @catalog_phase = :elbow
        @orthogonal_axis_lock = nil
        reset_typed_length
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        update_catalog_status
        true
      rescue => error
        puts "DuctToolCatalogWorkflow.place_catalog_straight_run failed: #{error.message}"
        puts error.backtrace.join("\n")
        true
      end

      def catalog_run_end_point(start_point, raw_point, typed_length: nil)
        return nil unless start_point

        # After a fitting exists, its outlet vector is authoritative. Cursor
        # movement changes only the run length; it can no longer steer the duct.
        if @last_port
          direction = normalized_vector(@last_port.outward_vector)
          return nil unless direction

          length = typed_length.to_f
          if length <= 0.0
            return nil unless raw_point
            length = start_point.vector_to(raw_point).dot(direction)
            length = round_to_increment(length, @length_increment)
          end
          return nil if length <= 0.0
          return start_point.offset(direction, length)
        end

        return nil unless raw_point
        if typed_length && typed_length.to_f > 0.0
          direction = typed_length_direction(start_point, raw_point)
          return direction ? start_point.offset(direction, typed_length.to_f) : nil
        end

        pending_build_point(start_point, raw_point)
      rescue
        nil
      end

      def catalog_phase_for_snapped_port(port)
        piece_type = port && port.piece && port.piece.type.to_sym
        # An outlet that already belongs to a stocked fitting is ready for its
        # following straight run. A bare pipe end expects the selected elbow.
        [:elbow, :tee, :wye, :reducer].include?(piece_type) ? :run : :elbow
      rescue
        :elbow
      end

      def catalog_connection_choice(port, raw_point)
        return nil unless port && raw_point
        entry = normalized_vector(port.outward_vector)
        return nil unless entry

        toward_cursor = port.point.vector_to(raw_point)
        return nil if toward_cursor.length <= PREVIEW_MIN_LENGTH
        toward_cursor.normalize!

        # If an axis lock is active and points along the existing outlet, the
        # user's explicit instruction is to continue straight. If the lock points
        # perpendicular to the outlet, it is reserved for the elbow turn.
        forced = forced_axis_direction(toward_cursor) if @orthogonal_axis_lock
        if forced
          forced = normalized_vector(forced)
          if forced
            return :straight if forced.dot(entry) > CATALOG_DIRECTION_DOT
            return :elbow if forced.dot(entry).abs < 0.05
          end
        end

        # Without an axis lock, a click clearly in front of the current port is
        # interpreted as "continue straight". Side clicks remain elbow choices.
        toward_cursor.dot(entry) >= 0.78 ? :straight : :elbow
      rescue
        nil
      end

      def catalog_elbow_exit_direction(port, raw_point, product)
        return nil unless port && raw_point && product
        entry = normalized_vector(port.outward_vector)
        return nil unless entry

        toward_cursor = port.point.vector_to(raw_point)
        return nil if toward_cursor.length <= PREVIEW_MIN_LENGTH

        dims = Model::DuctDimensions.coerce(port.dimensions)

        # Axis lock is authoritative in catalog mode. Unlike the old v2 behavior,
        # changing the inference color now changes the actual fitting direction.
        if @orthogonal_axis_lock
          forced = catalog_forced_turn_direction(entry, toward_cursor)
          return nil unless forced

          if dims.rectangular?
            basis = Geometry::RectangularFrame.basis_for_axis(
              entry,
              preferred_width_axis: port.width_axis,
              preferred_height_axis: port.height_axis
            )
            return nil unless basis
            allowed_axis = product.style == :long_way_miter ? basis[:width_axis] : basis[:height_axis]
            allowed_axis = Geometry::VectorMath.perpendicularized(allowed_axis, entry)
            return nil unless allowed_axis
            allowed_axis.normalize!
            return nil if forced.dot(allowed_axis).abs < CATALOG_DIRECTION_DOT
          end

          return forced
        end

        if dims.rectangular?
          basis = Geometry::RectangularFrame.basis_for_axis(
            entry,
            preferred_width_axis: port.width_axis,
            preferred_height_axis: port.height_axis
          )
          return nil unless basis

          bend_axis = product.style == :long_way_miter ? basis[:width_axis] : basis[:height_axis]
          bend_axis = Geometry::VectorMath.perpendicularized(bend_axis, entry)
          return nil unless bend_axis
          bend_axis.normalize!
          opposite = bend_axis.clone.reverse
          return toward_cursor.dot(bend_axis) >= toward_cursor.dot(opposite) ? bend_axis : opposite
        end

        # Round catalog elbows may be clocked when installed, but Simple Duct's
        # strict catalog workflow snaps that installation to a world-cardinal
        # orthogonal direction. This prevents arbitrary swivel angles while still
        # allowing every practical X/Y/Z turn.
        candidates = catalog_cardinal_turn_candidates(entry)
        return nil if candidates.empty?
        candidates.max_by { |candidate| toward_cursor.dot(candidate) }
      rescue => error
        puts "DuctToolCatalogWorkflow.catalog_elbow_exit_direction failed: #{error.message}"
        nil
      end

      def catalog_forced_turn_direction(entry, toward_cursor)
        forced = forced_axis_direction(toward_cursor)
        forced = normalized_vector(forced)
        return nil unless forced
        return nil if forced.dot(entry).abs > CATALOG_DIRECTION_DOT
        forced
      rescue
        nil
      end

      def catalog_cardinal_turn_candidates(entry)
        axes = [
          Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(-1, 0, 0),
          Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, -1, 0),
          Geom::Vector3d.new(0, 0, 1), Geom::Vector3d.new(0, 0, -1)
        ]
        axes.select { |axis| axis.dot(entry).abs <= 0.05 }
      rescue
        []
      end

      def catalog_elbow_direction_error(port, product)
        if @orthogonal_axis_lock
          "The selected axis lock is not a legal turn direction for #{product.sku}. Choose an axis perpendicular to the current run#{product.rectangular? ? ' and compatible with this short-/long-way elbow' : ''}."
        elsif product.round?
          "Move toward an X, Y, or Z side of the current run to choose the snapped 90° direction, or click forward to continue straight."
        else
          "Move to the allowed side of the rigid #{product.sku} elbow, or click forward to continue straight."
        end
      rescue
        "Choose a legal catalog elbow direction or continue straight."
      end

      def draw_catalog_preview(view)
        return false unless catalog_workflow_active?
        start_point = active_route_start_point
        return true unless start_point

        raw_point = preview_raw_point(view, start_point)
        return true unless raw_point

        if catalog_phase == :elbow && @last_port
          dimensions = Model::Port.dimensions_from_params({}, @last_port)
          entry = normalized_vector(@last_port.outward_vector)
          return true unless entry

          if catalog_connection_choice(@last_port, raw_point) == :straight
            preview_length = [Model::DuctDimensions.coerce(dimensions).largest * 1.5, 12.0].max
            endpoint = start_point.offset(entry, preview_length)
            draw_preview_lines(view, [start_point, endpoint], nil, line_width: 3)
            return true
          end

          product = Catalog::Manager.preferred_elbow(Sketchup.active_model, dimensions)
          return true unless product
          exitv = catalog_elbow_exit_direction(@last_port, raw_point, product)
          return true unless exitv

          radius = Catalog::Manager.elbow_bend_radius(product, dimensions, dimensions.largest)
          corner = start_point.offset(entry, radius)
          endpoint = corner.offset(exitv, radius)
          draw_preview_lines(view, [start_point, corner, corner, endpoint], nil, line_width: 3)
          return true
        end

        typed = typed_length_active? ? typed_length_total_inches : nil
        endpoint = catalog_run_end_point(start_point, raw_point, typed_length: typed)
        return true unless endpoint
        return true if start_point.distance(endpoint) < PREVIEW_MIN_LENGTH

        draw_preview_centerline(view, start_point, endpoint, nil)
        draw_ghost_duct_preview(view, start_point, endpoint, nil)
        true
      rescue => error
        puts "DuctToolCatalogWorkflow.draw_catalog_preview failed: #{error.message}"
        true
      end

      def commit_catalog_typed_length(view)
        return false unless catalog_workflow_active?
        return false unless catalog_phase == :run

        length = typed_length_total_inches
        return false unless length && length > 0.0

        start_point = active_route_start_point
        return false unless start_point
        raw_point = preview_raw_point(view, start_point)
        raw_point ||= start_point.offset(fallback_typed_length_direction, 1.0)

        place_catalog_straight_run(
          view,
          @last_mouse_x || 0,
          @last_mouse_y || 0,
          raw_point,
          snapped_port: nil,
          typed_length: length
        )
        view.invalidate if view
        true
      rescue => error
        puts "DuctToolCatalogWorkflow.commit_catalog_typed_length failed: #{error.message}"
        false
      end

      def current_dimensions
        Model::DuctDimensions.new(
          shape: @duct_shape,
          diameter: @current_diameter,
          width: @current_width,
          height: @current_height
        )
      end

      def choose_catalog_products_from_menu
        settings = Catalog::Manager.prompt_duct_settings(
          model: Sketchup.active_model,
          current_shape: @duct_shape,
          current_diameter: @current_diameter,
          current_width: @current_width,
          current_height: @current_height,
          current_increment: @length_increment
        )
        return unless settings

        @duct_shape = settings[:shape]
        @current_diameter = settings[:diameter].to_f
        @current_width = settings[:width].to_f
        @current_height = settings[:height].to_f
        @length_increment = settings[:length_increment].to_f
        @fitting_mode = :elbow
        @start_point = nil
        @last_port = nil
        reset_catalog_workflow!
        reset_typed_length
        update_catalog_status
      rescue => error
        puts "DuctToolCatalogWorkflow.choose_catalog_products_from_menu failed: #{error.message}"
      end

      def show_current_catalog_options
        Catalog::Manager.show_catalog_browser(
          Sketchup.active_model,
          dimensions: current_dimensions
        )
      rescue => error
        puts "DuctToolCatalogWorkflow.show_current_catalog_options failed: #{error.message}"
      end

      def current_catalog_product_summary
        dims = current_dimensions
        pipe = Catalog::Manager.pipe_product(dims, Sketchup.active_model)
        elbow = Catalog::Manager.preferred_elbow(Sketchup.active_model, dims)
        "Pipe #{pipe ? pipe.sku : 'none'}; elbow #{elbow ? elbow.sku : 'none'}"
      rescue
        "catalog products unavailable"
      end

      def update_catalog_status
        return nil unless Catalog::Manager.active?(Sketchup.active_model)

        dims = current_dimensions
        pipe = Catalog::Manager.pipe_product(dims, Sketchup.active_model)
        elbow = Catalog::Manager.preferred_elbow(Sketchup.active_model, dims)
        size = Catalog::Manager.dimensions_label(dims)

        if @fitting_mode && @fitting_mode != :elbow
          component_label = {
            tee: "Add Tee",
            end_tee: "End Tee",
            end_wye: "End Wye",
            end_reducer: "End Reducer / Converter",
            vent: "End Cover"
          }[@fitting_mode] || @fitting_mode.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
          Sketchup.status_text = "Master Flow #{size}: #{component_label} mode. Only matching catalog products can be placed."
          return true
        end

        message =
          case catalog_phase
          when :elbow
            if elbow
              "Master Flow #{size}: click FORWARD to continue straight, or click to a legal side to place rigid #{elbow.sku}. Then click again to set the run length."
            else
              "Master Flow #{size}: no catalog elbow exists. Click FORWARD to continue straight, or use a listed catalog transition to change size."
            end
          when :run
            if @last_port
              "Master Flow #{size}: click ahead to set the length of #{pipe ? pipe.sku : 'the catalog straight duct'}. Direction is locked to the fitting outlet."
            else
              "Master Flow #{size}: click to place the first #{pipe ? pipe.sku : 'catalog straight duct'} run."
            end
          else
            "Master Flow #{size}: click an open port to attach, or click empty space to begin. #{current_catalog_product_summary}."
          end

        axis_lock_text = orthogonal_axis_lock_label
        message += " #{axis_lock_text}." if axis_lock_text
        if typed_length_active?
          message += " Typed length: #{typed_length_status_text}."
        end
        Sketchup.status_text = message
      rescue => error
        puts "DuctToolCatalogWorkflow.update_catalog_status failed: #{error.message}"
      end

      def update_catalog_mouse_status(_view = nil, _x = nil, _y = nil)
        update_catalog_status
      end
    end
  end
end
