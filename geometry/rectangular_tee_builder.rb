module DuctExtension
  module Geometry
    module RectangularTeeBuilder
      SOCKET_DEPTH_FACTOR = 0.82
      EPSILON = 0.000001

      def self.socket_depth(width, height)
        [width.to_f, height.to_f].max * SOCKET_DEPTH_FACTOR
      end

      def self.build_into(
        group,
        center,
        branch_base,
        main_vector,
        branch_vector,
        width,
        height,
        socket_depth = nil,
        preferred_main_width_axis: nil,
        preferred_main_height_axis: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        branch_base = RectangularFrame.point3d(branch_base)

        main_vector = RectangularFrame.normalized(main_vector)
        branch_vector = RectangularFrame.normalized(branch_vector)

        width = width.to_f
        height = height.to_f
        depth = socket_depth ? socket_depth.to_f : self.socket_depth(width, height)

        return false unless center && branch_base && main_vector && branch_vector
        return false if width <= 0.0 || height <= 0.0 || depth <= 0.0
        return false if main_vector.parallel?(branch_vector)

        main_basis = rectangular_basis(
          main_vector,
          width,
          height,
          preferred_width_axis: preferred_main_width_axis,
          preferred_height_axis: preferred_main_height_axis,
          allow_relevel: false
        )

        return false unless main_basis

        tee_plane_normal = main_vector.cross(branch_vector)
        return false if tee_plane_normal.length <= EPSILON
        tee_plane_normal.normalize!

        # Keep the extrusion/thickness direction aligned with the main duct's
        # existing rectangular frame when possible. This is what keeps the tee
        # from randomly rolling.
        if main_basis[:height_axis] && tee_plane_normal.dot(main_basis[:height_axis]) < 0.0
          tee_plane_normal.reverse!
        end

        main_side_axis = branch_vector.clone
        main_side_axis.normalize!

        # If the requested branch vector points opposite the actual branch base,
        # flip it so the visual tee grows toward the branch socket.
        center_to_branch_base = center.vector_to(branch_base)
        if center_to_branch_base.length > EPSILON && center_to_branch_base.dot(main_side_axis) < 0.0
          main_side_axis.reverse!
        end

        main_a = center.offset(main_vector.clone.reverse, depth)
        main_b = center.offset(main_vector, depth)

        face_offset = center.vector_to(branch_base).dot(main_side_axis).abs

        if face_offset <= EPSILON
          face_offset = half_extent_for_direction(
            direction: main_side_axis,
            width: width,
            height: height,
            basis: main_basis
          )
        end

        thickness_half = half_extent_for_direction(
          direction: tee_plane_normal,
          width: width,
          height: height,
          basis: main_basis
        )

        thickness_half = height / 2.0 if thickness_half <= EPSILON

        branch_axis = main_side_axis
        branch_end = center.offset(branch_axis, face_offset + depth)

        # Branch width lies across the tee, along the main run.
        branch_width_axis = main_vector.clone
        branch_width_axis.normalize!

        branch_height_axis = tee_plane_normal.clone
        branch_height_axis.normalize!

        build_formed_rectangular_tee_body(
          group: group,
          center: center,
          main_axis: main_vector,
          branch_axis: branch_axis,
          thickness_axis: tee_plane_normal,
          width: width,
          height: height,
          main_depth: depth,
          branch_depth: depth,
          face_offset: face_offset,
          thickness_half: thickness_half
        )

        add_socket_outline_edges(
          group: group,
          center: main_a,
          width_axis: main_side_axis,
          height_axis: tee_plane_normal,
          half_width: face_offset,
          half_height: thickness_half
        )

        add_socket_outline_edges(
          group: group,
          center: main_b,
          width_axis: main_side_axis,
          height_axis: tee_plane_normal,
          half_width: face_offset,
          half_height: thickness_half
        )

        add_socket_outline_edges(
          group: group,
          center: branch_end,
          width_axis: branch_width_axis,
          height_axis: branch_height_axis,
          half_width: width / 2.0,
          half_height: thickness_half
        )

        add_sheet_metal_break_lines(
          group: group,
          center: center,
          main_axis: main_vector,
          branch_axis: branch_axis,
          thickness_axis: tee_plane_normal,
          main_depth: depth,
          face_offset: face_offset,
          branch_depth: depth,
          branch_half_width: width / 2.0,
          thickness_half: thickness_half
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "RectangularTeeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_formed_rectangular_tee_body(
        group:,
        center:,
        main_axis:,
        branch_axis:,
        thickness_axis:,
        width:,
        height:,
        main_depth:,
        branch_depth:,
        face_offset:,
        thickness_half:
      )
        entities = group.entities

        branch_half_width = width.to_f / 2.0

        main_left = -main_depth
        main_right = main_depth
        main_back = -face_offset
        main_front = face_offset

        branch_left = -branch_half_width
        branch_right = branch_half_width
        branch_front = face_offset + branch_depth

        # Main through-body footprint.
        main_bottom_left = [main_left, main_back]
        main_bottom_right = [main_right, main_back]
        main_top_right = [main_right, main_front]
        main_top_left = [main_left, main_front]

        # Branch footprint. It begins exactly on the side face of the main duct,
        # so the tee reads as one formed fitting instead of a box sitting over it.
        branch_base_left = [branch_left, main_front]
        branch_base_right = [branch_right, main_front]
        branch_end_right = [branch_right, branch_front]
        branch_end_left = [branch_left, branch_front]

        main_top = [
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_bottom_left[0], main_bottom_left[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_bottom_right[0], main_bottom_right[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_top_right[0], main_top_right[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_top_left[0], main_top_left[1], thickness_half)
        ]

        main_bottom = [
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_bottom_left[0], main_bottom_left[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_bottom_right[0], main_bottom_right[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_top_right[0], main_top_right[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, main_top_left[0], main_top_left[1], -thickness_half)
        ]

        branch_top = [
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_base_left[0], branch_base_left[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_base_right[0], branch_base_right[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_end_right[0], branch_end_right[1], thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_end_left[0], branch_end_left[1], thickness_half)
        ]

        branch_bottom = [
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_base_left[0], branch_base_left[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_base_right[0], branch_base_right[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_end_right[0], branch_end_right[1], -thickness_half),
          point_from_tee_offsets(center, main_axis, branch_axis, thickness_axis, branch_end_left[0], branch_end_left[1], -thickness_half)
        ]

        # Top and bottom sheet-metal faces.
        Mesh.add_face_safe(entities, main_top)
        Mesh.add_face_safe(entities, main_bottom.reverse)

        Mesh.add_face_safe(entities, branch_top)
        Mesh.add_face_safe(entities, branch_bottom.reverse)

        # Main back wall.
        add_wall_from_2d(
          entities: entities,
          center: center,
          main_axis: main_axis,
          branch_axis: branch_axis,
          thickness_axis: thickness_axis,
          a: main_bottom_left,
          b: main_bottom_right,
          thickness_half: thickness_half
        )

        # Main front wall, split around the branch opening.
        if branch_left > main_left + EPSILON
          add_wall_from_2d(
            entities: entities,
            center: center,
            main_axis: main_axis,
            branch_axis: branch_axis,
            thickness_axis: thickness_axis,
            a: main_top_left,
            b: branch_base_left,
            thickness_half: thickness_half
          )
        end

        if branch_right < main_right - EPSILON
          add_wall_from_2d(
            entities: entities,
            center: center,
            main_axis: main_axis,
            branch_axis: branch_axis,
            thickness_axis: thickness_axis,
            a: branch_base_right,
            b: main_top_right,
            thickness_half: thickness_half
          )
        end

        # Branch side walls.
        add_wall_from_2d(
          entities: entities,
          center: center,
          main_axis: main_axis,
          branch_axis: branch_axis,
          thickness_axis: thickness_axis,
          a: branch_base_left,
          b: branch_end_left,
          thickness_half: thickness_half
        )

        add_wall_from_2d(
          entities: entities,
          center: center,
          main_axis: main_axis,
          branch_axis: branch_axis,
          thickness_axis: thickness_axis,
          a: branch_base_right,
          b: branch_end_right,
          thickness_half: thickness_half
        )

        # Main left and right end openings are intentionally left open.
        # Branch end opening is intentionally left open.

        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, main_bottom_left, main_bottom_right, thickness_half)
        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, main_bottom_left, main_bottom_right, -thickness_half)

        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, main_top_left, branch_base_left, thickness_half)
        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, main_top_left, branch_base_left, -thickness_half)

        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_right, main_top_right, thickness_half)
        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_right, main_top_right, -thickness_half)

        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_left, branch_end_left, thickness_half)
        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_left, branch_end_left, -thickness_half)

        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_right, branch_end_right, thickness_half)
        add_visible_edge_2d(group, center, main_axis, branch_axis, thickness_axis, branch_base_right, branch_end_right, -thickness_half)

        true
      rescue => error
        puts "RectangularTeeBuilder.build_formed_rectangular_tee_body failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.add_sheet_metal_break_lines(
        group:,
        center:,
        main_axis:,
        branch_axis:,
        thickness_axis:,
        main_depth:,
        face_offset:,
        branch_depth:,
        branch_half_width:,
        thickness_half:
      )
        # These crease lines are deliberately simple. They make the tee read as a
        # formed sheet-metal fitting, not just two plain boxes.
        entities = group.entities

        left_base = [-branch_half_width, face_offset]
        right_base = [branch_half_width, face_offset]
        left_end = [-branch_half_width, face_offset + branch_depth]
        right_end = [branch_half_width, face_offset + branch_depth]

        [
          [left_base, left_end],
          [right_base, right_end],
          [left_base, right_base]
        ].each do |pair|
          a, b = pair

          add_visible_edge_2d(
            group,
            center,
            main_axis,
            branch_axis,
            thickness_axis,
            a,
            b,
            thickness_half
          )

          add_visible_edge_2d(
            group,
            center,
            main_axis,
            branch_axis,
            thickness_axis,
            a,
            b,
            -thickness_half
          )
        end

        # Add main opening split lines at the three rectangular sockets.
        [
          [-main_depth, -face_offset],
          [-main_depth, face_offset],
          [main_depth, -face_offset],
          [main_depth, face_offset],
          [-branch_half_width, face_offset + branch_depth],
          [branch_half_width, face_offset + branch_depth]
        ].each do |point_2d|
          top = point_from_tee_offsets(
            center,
            main_axis,
            branch_axis,
            thickness_axis,
            point_2d[0],
            point_2d[1],
            thickness_half
          )

          bottom = point_from_tee_offsets(
            center,
            main_axis,
            branch_axis,
            thickness_axis,
            point_2d[0],
            point_2d[1],
            -thickness_half
          )

          add_visible_edge(entities, top, bottom)
        end
      rescue => error
        puts "RectangularTeeBuilder.add_sheet_metal_break_lines failed: #{error.message}"
      end

      def self.add_wall_from_2d(
        entities:,
        center:,
        main_axis:,
        branch_axis:,
        thickness_axis:,
        a:,
        b:,
        thickness_half:
      )
        top_a = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          a[0],
          a[1],
          thickness_half
        )

        top_b = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          b[0],
          b[1],
          thickness_half
        )

        bottom_b = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          b[0],
          b[1],
          -thickness_half
        )

        bottom_a = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          a[0],
          a[1],
          -thickness_half
        )

        Mesh.add_quad(
          entities,
          top_a,
          top_b,
          bottom_b,
          bottom_a
        )
      rescue => error
        puts "RectangularTeeBuilder.add_wall_from_2d failed: #{error.message}"
      end

      def self.add_socket_outline_edges(
        group:,
        center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:
      )
        entities = group.entities

        corners = rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        return if corners.empty?

        4.times do |index|
          add_visible_edge(
            entities,
            corners[index],
            corners[(index + 1) % 4]
          )
        end
      rescue => error
        puts "RectangularTeeBuilder.add_socket_outline_edges failed: #{error.message}"
      end

      def self.rectangle_corners(
        center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:
      )
        PrimitiveHelpers.rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height,
          normalize_axes: true
        )
      end

      def self.point_from_tee_offsets(
        center,
        main_axis,
        branch_axis,
        thickness_axis,
        main_offset,
        branch_offset,
        thickness_offset
      )
        Geom::Point3d.new(
          center.x +
            main_axis.x * main_offset.to_f +
            branch_axis.x * branch_offset.to_f +
            thickness_axis.x * thickness_offset.to_f,

          center.y +
            main_axis.y * main_offset.to_f +
            branch_axis.y * branch_offset.to_f +
            thickness_axis.y * thickness_offset.to_f,

          center.z +
            main_axis.z * main_offset.to_f +
            branch_axis.z * branch_offset.to_f +
            thickness_axis.z * thickness_offset.to_f
        )
      end

      def self.add_visible_edge_2d(
        group,
        center,
        main_axis,
        branch_axis,
        thickness_axis,
        a,
        b,
        thickness_offset
      )
        entities = group.entities

        point_a = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          a[0],
          a[1],
          thickness_offset
        )

        point_b = point_from_tee_offsets(
          center,
          main_axis,
          branch_axis,
          thickness_axis,
          b[0],
          b[1],
          thickness_offset
        )

        add_visible_edge(entities, point_a, point_b)
      rescue
        nil
      end

      def self.add_visible_edge(entities, point_a, point_b)
        PrimitiveHelpers.add_visible_edge(
          entities,
          point_a,
          point_b,
          min_distance: EPSILON
        )
      end

      def self.half_extent_for_direction(direction:, width:, height:, basis:)
        return 0.0 unless direction && basis

        direction = RectangularFrame.normalized(direction)
        return 0.0 unless direction

        width_axis = basis[:width_axis]
        height_axis = basis[:height_axis]

        width_dot = width_axis ? direction.dot(width_axis).abs : 0.0
        height_dot = height_axis ? direction.dot(height_axis).abs : 0.0

        if width_dot >= height_dot
          width.to_f / 2.0
        else
          height.to_f / 2.0
        end
      rescue
        0.0
      end

      def self.rectangular_basis(
        axis,
        width,
        height,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        allow_relevel: false
      )
        if RectangularFrame.respond_to?(:stable_basis_for_axis)
          RectangularFrame.stable_basis_for_axis(
            axis,
            width,
            height,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis,
            allow_relevel: allow_relevel
          )
        else
          RectangularFrame.basis_for_axis(
            axis,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
        end
      rescue
        RectangularFrame.basis_for_axis(
          axis,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      end
    end
  end
end
