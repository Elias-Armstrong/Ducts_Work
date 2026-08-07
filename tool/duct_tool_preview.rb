module DuctExtension
  module Tool
    module DuctToolRoutingPreview
      private

      def connect_to_target_port(target_port)
        return nil unless target_port

        Services::PortToPortRouteService.connect(
          model: Sketchup.active_model,
          network: @network,
          source_port: @last_port,
          source_point: @start_point,
          target_port: target_port,
          diameter: @current_diameter,
          shape: @duct_shape,
          width: @current_width,
          height: @current_height,
          fitting_mode: @fitting_mode
        )
      end

      def finish_connection(view, message)
        @last_port = nil
        @start_point = nil
        @orthogonal_axis_lock = nil
        reset_catalog_workflow! if respond_to?(:reset_catalog_workflow!, true)
        @network.rebuild_index! if @network.respond_to?(:rebuild_index!)
        Sketchup.status_text = message
        view.invalidate if view
      end

      def active_route_start_point
        if @last_port
          @last_port.point
        elsif @start_point
          @start_point
        else
          nil
        end
      end

      def preview_raw_point(view, start_point)
        if @last_mouse_x && @last_mouse_y
          projected = mouse_projected_point(view, @last_mouse_x, @last_mouse_y, start_point)
          return projected if projected
        end

        return @current_ip.position if @current_ip.valid?

        nil
      end

      def click_route_point(view, x, y, start_point, fallback_point)
        projected = mouse_projected_point(view, x, y, start_point)
        projected || fallback_point
      rescue => error
        puts "Click route point failed: #{error.message}"
        fallback_point
      end

      def current_preview_snapped_port(view, raw_point)
        return nil unless view
        return nil unless @last_mouse_x && @last_mouse_y
        return nil unless raw_point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: @last_mouse_x,
          y: @last_mouse_y,
          point: raw_point
        )

        snap&.port
      rescue => error
        puts "Preview snap check failed: #{error.message}"
        nil
      end

      def pending_build_point(start_point, raw_point)
        return raw_point unless start_point
        return raw_point unless raw_point

        snapped = orthogonal_snap_point(start_point, raw_point)
        quantize_point_from_start(start_point, snapped)
      end

      def orthogonal_snap_point(start_point, raw_point)
        vector = start_point.vector_to(raw_point)
        return raw_point if vector.length == 0

        length = vector.length
        direction = vector.clone
        direction.normalize!

        snapped_direction =
          if @orthogonal_axis_lock
            forced_axis_direction(direction)
          else
            nearest_allowed_route_direction(direction)
          end

        return raw_point unless snapped_direction

        start_point.offset(snapped_direction, length)
      end

      def nearest_allowed_route_direction(direction)
        direction = normalized_vector(direction)
        return nil unless direction

        candidates = allowed_route_directions

        best = candidates.max_by do |candidate|
          candidate.dot(direction)
        end

        best && best.clone
      end

      def allowed_route_directions
        @allowed_route_directions ||= begin
          directions = []

          x_axis = Geom::Vector3d.new(1, 0, 0)
          y_axis = Geom::Vector3d.new(0, 1, 0)
          z_axis = Geom::Vector3d.new(0, 0, 1)

          add_direction_pair(directions, x_axis)
          add_direction_pair(directions, y_axis)
          add_direction_pair(directions, z_axis)

          add_plane_45_directions(directions, :xy)
          add_plane_45_directions(directions, :xz)
          add_plane_45_directions(directions, :yz)

          unique_directions(directions)
        end
      end

      def add_plane_45_directions(directions, plane)
        c = Math.cos(45.degrees)
        s = Math.sin(45.degrees)

        [-1, 1].each do |a_sign|
          [-1, 1].each do |b_sign|
            case plane
            when :xy
              directions << normalized_vector(Geom::Vector3d.new(c * a_sign, s * b_sign, 0))
            when :xz
              directions << normalized_vector(Geom::Vector3d.new(c * a_sign, 0, s * b_sign))
            when :yz
              directions << normalized_vector(Geom::Vector3d.new(0, c * a_sign, s * b_sign))
            end
          end
        end
      end

      def add_direction_pair(directions, vector)
        v = normalized_vector(vector)
        return unless v

        directions << v
        directions << v.clone.reverse
      end

      def unique_directions(directions)
        clean = []

        directions.each do |direction|
          next unless direction

          duplicate = clean.any? do |existing|
            existing.angle_between(direction) < 0.001
          end

          clean << direction unless duplicate
        end

        clean
      end

      def quantize_point_from_start(start_point, raw_point)
        vector = start_point.vector_to(raw_point)
        return raw_point if vector.length == 0

        raw_length = vector.length
        rounded_length = round_to_increment(raw_length, @length_increment)

        return start_point if rounded_length <= 0.0

        direction = vector.clone
        direction.normalize!

        start_point.offset(direction, rounded_length)
      end

      def draw_preview_centerline(view, start_point, end_point, snapped_port)
        draw_preview_lines(view, [start_point, end_point], snapped_port, line_width: 2)
      end

      def draw_ghost_duct_preview(view, start_point, end_point, snapped_port)
        if @duct_shape == :rectangular
          draw_rectangular_ghost_preview(view, start_point, end_point, snapped_port)
        else
          draw_round_ghost_preview(view, start_point, end_point, snapped_port)
        end
      end

      def draw_rectangular_ghost_preview(view, start_point, end_point, snapped_port)
        direction = start_point.vector_to(end_point)
        return if direction.length < PREVIEW_MIN_LENGTH

        direction.normalize!

        width_axis, height_axis = preview_rectangular_axes(direction)
        return unless width_axis && height_axis

        half_width = @current_width.to_f / 2.0
        half_height = @current_height.to_f / 2.0

        start_corners = Geometry::PrimitiveHelpers.rectangle_corners(
          center: start_point, width_axis: width_axis, height_axis: height_axis,
          half_width: half_width, half_height: half_height
        )
        end_corners = Geometry::PrimitiveHelpers.rectangle_corners(
          center: end_point, width_axis: width_axis, height_axis: height_axis,
          half_width: half_width, half_height: half_height
        )

        lines = []

        4.times do |i|
          next_i = (i + 1) % 4

          lines << start_corners[i]
          lines << start_corners[next_i]

          lines << end_corners[i]
          lines << end_corners[next_i]

          lines << start_corners[i]
          lines << end_corners[i]
        end

        draw_preview_lines(view, lines, snapped_port)
      end

      def draw_round_ghost_preview(view, start_point, end_point, snapped_port)
        direction = start_point.vector_to(end_point)
        return if direction.length < PREVIEW_MIN_LENGTH

        direction.normalize!

        axis_a, axis_b = preview_round_axes(direction)
        return unless axis_a && axis_b

        radius = @current_diameter.to_f / 2.0
        start_ring = []
        end_ring = []

        PREVIEW_ROUND_SEGMENTS.times do |index|
          angle = (Math::PI * 2.0 * index) / PREVIEW_ROUND_SEGMENTS

          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )

          radial.normalize!

          start_ring << start_point.offset(radial, radius)
          end_ring << end_point.offset(radial, radius)
        end

        lines = []

        PREVIEW_ROUND_SEGMENTS.times do |index|
          next_index = (index + 1) % PREVIEW_ROUND_SEGMENTS

          lines << start_ring[index]
          lines << start_ring[next_index]

          lines << end_ring[index]
          lines << end_ring[next_index]

          if index.even?
            lines << start_ring[index]
            lines << end_ring[index]
          end
        end

        draw_preview_lines(view, lines, snapped_port)
      end

      # Preview geometry is calculated in 3D, then rendered as a screen-space
      # overlay. SketchUp can depth-hide view.draw geometry behind the model at
      # certain camera angles; draw2d keeps the hologram visible without changing
      # the actual route points used for construction.
      def draw_preview_lines(view, points, snapped_port, line_width: 1)
        points = Array(points).compact
        return if points.empty?

        view.drawing_color = preview_color(snapped_port)
        view.line_width = line_width

        if view.respond_to?(:draw2d) && view.respond_to?(:screen_coords)
          screen_points = points.map { |point| view.screen_coords(point) }
          if screen_points.all?
            view.draw2d(GL_LINES, screen_points)
            return
          end
        end

        view.draw(GL_LINES, points)
      rescue => error
        puts "Preview overlay draw failed: #{error.message}"
        view.draw(GL_LINES, points) rescue nil
      end

      def preview_color(snapped_port)
        if snapped_port
          "green"
        elsif @orthogonal_axis_lock
          "orange"
        elsif typed_length_active?
          "blue"
        else
          "red"
        end
      end

      def preview_rectangular_axes(direction)
        preferred_width_axis =
          if @last_port && @last_port.respond_to?(:width_axis)
            @last_port.width_axis
          else
            nil
          end

        preferred_height_axis =
          if @last_port && @last_port.respond_to?(:height_axis)
            @last_port.height_axis
          else
            nil
          end

        width_axis = perpendicularized_to_axis(preferred_width_axis, direction)
        width_axis ||= perpendicularized_to_axis(preferred_height_axis, direction)

        unless width_axis
          reference = preview_reference_axis(direction)
          width_axis = direction.cross(reference)
          return nil if width_axis.length == 0
          width_axis.normalize!
        end

        height_axis = direction.cross(width_axis)
        return nil if height_axis.length == 0

        height_axis.normalize!

        [width_axis, height_axis]
      end

      def preview_round_axes(direction)
        reference = preview_reference_axis(direction)

        axis_a = direction.cross(reference)
        return nil if axis_a.length == 0
        axis_a.normalize!

        axis_b = direction.cross(axis_a)
        return nil if axis_b.length == 0
        axis_b.normalize!

        [axis_a, axis_b]
      end

      def preview_reference_axis(direction)
        z_axis = Geom::Vector3d.new(0, 0, 1)

        if direction.dot(z_axis).abs < 0.95
          z_axis
        else
          Geom::Vector3d.new(1, 0, 0)
        end
      end

      def mouse_projected_point(view, x, y, start_point)
        ray = view.pickray(x, y)
        return nil unless ray

        ray_origin = ray[0]
        ray_vector = ray[1]

        return nil unless ray_origin
        return nil unless ray_vector
        return nil if ray_vector.length == 0

        camera_direction = view.camera.direction
        return nil unless camera_direction
        return nil if camera_direction.length == 0

        Geom.intersect_line_plane(
          [ray_origin, ray_vector],
          [start_point, camera_direction]
        )
      rescue => error
        puts "Mouse projected point failed: #{error.message}"
        nil
      end

      def update_length_status(view, x, y)
        if catalog_workflow_active?
          update_catalog_mouse_status(view, x, y)
          return
        end

        start = active_route_start_point

        unless start && @current_ip.valid?
          update_status_for_current_shape
          return
        end

        raw_point = click_route_point(view, x, y, start, @current_ip.position)
        return unless raw_point

        snap = Services::SnapService.find_open_external_port(
          network: @network,
          view: view,
          x: x,
          y: y,
          point: raw_point
        )

        snapped_port = typed_length_active? ? nil : snap&.port

        build_point =
          if typed_length_active?
            typed_length_preview_point(start, raw_point)
          elsif snapped_port
            snapped_port.point
          else
            pending_build_point(start, raw_point)
          end

        return unless build_point

        length = start.distance(build_point)

        shape_text =
          if @duct_shape == :rectangular
            "Rectangular #{@current_width}\" x #{@current_height}\""
          else
            "Round #{@current_diameter}\""
          end

        increment_text = increment_label(@length_increment)
        axis_lock_text = orthogonal_axis_lock_label

        snap_text =
          if typed_length_active?
            " | typed: #{typed_length_status_text} | Enter to draw, Backspace to edit, Esc to clear"
          elsif snapped_port
            " | snapping to port"
          elsif axis_lock_text
            " | Orthogonal Snap + #{increment_text} rounded | #{axis_lock_text}"
          else
            " | Orthogonal Snap + #{increment_text} rounded"
          end

        Sketchup.status_text =
          "#{shape_text} | pending length: #{format_length_increment(length)}#{snap_text}"
      rescue => error
        puts "Length status failed: #{error.message}"
      end

    end
  end
end
