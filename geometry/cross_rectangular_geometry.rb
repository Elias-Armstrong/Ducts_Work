# ===== Consolidated from: geometry/cross/rectangular_geometry.rb =====
module DuctExtension
  module Geometry
    module CrossBuilder
      def self.build_rectangular(
        group:,
        center:,
        forward_vector:,
        side_vector:,
        width:,
        height:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        branch_width: nil,
        branch_height: nil
      )
        return false if width <= 0.0 || height <= 0.0

        branch_width = branch_width.to_f
        branch_height = branch_height.to_f
        branch_width = width if branch_width <= 0.0
        branch_height = height if branch_height <= 0.0

        forward_axis = RectangularFrame.normalized(forward_vector)
        return false unless forward_axis

        side_axis = perpendicularized(preferred_width_axis, forward_axis)
        side_axis ||= perpendicularized(side_vector, forward_axis)
        return false unless side_axis

        height_axis = perpendicularized(preferred_height_axis, forward_axis)
        height_axis ||= forward_axis.cross(side_axis)
        return false unless height_axis && height_axis.length > 0

        height_axis.normalize!

        corrected_side = height_axis.cross(forward_axis)
        if corrected_side && corrected_side.length > 0
          corrected_side.normalize!
          side_axis = corrected_side
        end

        depth = socket_depth([width, branch_width].max, [height, branch_height].max)

        half_forward = width.to_f / 2.0 + RECTANGULAR_OVERLAP
        half_side = [width.to_f, branch_width.to_f].max / 2.0 + RECTANGULAR_OVERLAP
        half_height = [height.to_f, branch_height.to_f].max / 2.0 + RECTANGULAR_OVERLAP

        add_oriented_box(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          height_axis: height_axis,
          half_forward: half_forward,
          half_side: half_side,
          half_height: half_height
        )

        stem_end = center.offset(forward_axis.clone.reverse, depth)
        forward_end = center.offset(forward_axis, depth)
        left_end = center.offset(side_axis.clone.reverse, depth)
        right_end = center.offset(side_axis, depth)

        build_rectangular_socket(
          group: group,
          start_point: center,
          end_point: forward_end,
          width: width,
          height: height,
          width_axis: side_axis,
          height_axis: height_axis
        )

        build_rectangular_socket(
          group: group,
          start_point: center,
          end_point: stem_end,
          width: width,
          height: height,
          width_axis: side_axis,
          height_axis: height_axis
        )

        build_rectangular_socket(
          group: group,
          start_point: center,
          end_point: right_end,
          width: branch_width,
          height: branch_height,
          width_axis: forward_axis,
          height_axis: height_axis
        )

        build_rectangular_socket(
          group: group,
          start_point: center,
          end_point: left_end,
          width: branch_width,
          height: branch_height,
          width_axis: forward_axis,
          height_axis: height_axis
        )

        harden_all_rectangular_edges(group)

        hide_rectangular_cross_seams(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          height_axis: height_axis,
          half_forward: half_forward,
          half_side: half_side,
          half_height: half_height
        )

        add_rectangular_cross_boundary_edges(
          group: group,
          center: center,
          forward_axis: forward_axis,
          side_axis: side_axis,
          height_axis: height_axis,
          width: width,
          height: height,
          branch_width: branch_width,
          branch_height: branch_height,
          socket_depth: depth,
          half_forward: half_forward,
          half_side: half_side
        )

        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "CrossBuilder.build_rectangular failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular_socket(
        group:,
        start_point:,
        end_point:,
        width:,
        height:,
        width_axis:,
        height_axis:
      )
        RectangularPipeBuilder.build_into(
          group,
          start_point,
          end_point,
          width,
          height,
          overlap_start: true,
          overlap_end: false,
          cap_start: false,
          cap_end: false,
          preferred_width_axis: width_axis,
          preferred_height_axis: height_axis
        )
      end

      def self.add_oriented_box(
        group:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        half_forward:,
        half_side:,
        half_height:
      )
        entities = group.entities

        f = forward_axis
        s = side_axis
        h = height_axis

        hf = half_forward.to_f
        hs = half_side.to_f
        hh = half_height.to_f

        p000 = box_point(center, f, s, h, -hf, -hs, -hh)
        p001 = box_point(center, f, s, h, -hf, -hs,  hh)
        p010 = box_point(center, f, s, h, -hf,  hs, -hh)
        p011 = box_point(center, f, s, h, -hf,  hs,  hh)

        p100 = box_point(center, f, s, h,  hf, -hs, -hh)
        p101 = box_point(center, f, s, h,  hf, -hs,  hh)
        p110 = box_point(center, f, s, h,  hf,  hs, -hh)
        p111 = box_point(center, f, s, h,  hf,  hs,  hh)

        Mesh.add_quad(entities, p000, p001, p011, p010)
        Mesh.add_quad(entities, p100, p110, p111, p101)
        Mesh.add_quad(entities, p000, p100, p101, p001)
        Mesh.add_quad(entities, p010, p011, p111, p110)
        Mesh.add_quad(entities, p000, p010, p110, p100)
        Mesh.add_quad(entities, p001, p101, p111, p011)
      rescue => error
        puts "CrossBuilder.add_oriented_box failed: #{error.message}"
      end

      def self.harden_all_rectangular_edges(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.hidden = false
          edge.soft = false if edge.respond_to?(:soft=)
          edge.smooth = false if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "CrossBuilder.harden_all_rectangular_edges failed: #{error.message}"
      end

      def self.hide_rectangular_cross_seams(
        group:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        half_forward:,
        half_side:,
        half_height:
      )
        padding = RECTANGULAR_SEAM_HIDE_PADDING.to_f

        forward_limit = half_forward.to_f + padding
        side_limit = half_side.to_f + padding
        height_limit = half_height.to_f + padding

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          midpoint = edge_midpoint(edge)
          next unless midpoint

          local = local_coords(
            point: midpoint,
            center: center,
            forward_axis: forward_axis,
            side_axis: side_axis,
            height_axis: height_axis
          )

          next unless local

          if local[:forward].abs <= forward_limit &&
             local[:side].abs <= side_limit &&
             local[:height].abs <= height_limit

            edge.hidden = true
            edge.soft = false if edge.respond_to?(:soft=)
            edge.smooth = false if edge.respond_to?(:smooth=)
          end
        end
      rescue => error
        puts "CrossBuilder.hide_rectangular_cross_seams failed: #{error.message}"
      end

      def self.add_rectangular_cross_boundary_edges(
        group:,
        center:,
        forward_axis:,
        side_axis:,
        height_axis:,
        width:,
        height:,
        branch_width:,
        branch_height:,
        socket_depth:,
        half_forward:,
        half_side:
      )
        entities = group.entities

        main_half_width = width.to_f / 2.0
        main_half_height = height.to_f / 2.0
        side_half_width = branch_width.to_f / 2.0
        side_half_height = branch_height.to_f / 2.0

        # Important:
        # Do NOT redraw the central plenum box outline. That is what created
        # the unwanted square/rectangle in the middle of the cross. Instead,
        # redraw only the true outside/open-end boundaries of the four socket
        # segments.

        add_rectangular_prism_outline_edges(
          entities: entities,
          start_center: center.offset(forward_axis, half_forward),
          end_center: center.offset(forward_axis, socket_depth),
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: main_half_width,
          half_height: main_half_height,
          include_start_ring: false,
          include_end_ring: true
        )

        add_rectangular_prism_outline_edges(
          entities: entities,
          start_center: center.offset(forward_axis.clone.reverse, half_forward),
          end_center: center.offset(forward_axis.clone.reverse, socket_depth),
          width_axis: side_axis,
          height_axis: height_axis,
          half_width: main_half_width,
          half_height: main_half_height,
          include_start_ring: false,
          include_end_ring: true
        )

        add_rectangular_prism_outline_edges(
          entities: entities,
          start_center: center.offset(side_axis, half_side),
          end_center: center.offset(side_axis, socket_depth),
          width_axis: forward_axis,
          height_axis: height_axis,
          half_width: side_half_width,
          half_height: side_half_height,
          include_start_ring: false,
          include_end_ring: true
        )

        add_rectangular_prism_outline_edges(
          entities: entities,
          start_center: center.offset(side_axis.clone.reverse, half_side),
          end_center: center.offset(side_axis.clone.reverse, socket_depth),
          width_axis: forward_axis,
          height_axis: height_axis,
          half_width: side_half_width,
          half_height: side_half_height,
          include_start_ring: false,
          include_end_ring: true
        )

        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = false if edge.respond_to?(:soft=)
          edge.smooth = false if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "CrossBuilder.add_rectangular_cross_boundary_edges failed: #{error.message}"
      end

      def self.add_rectangular_prism_outline_edges(
        entities:,
        start_center:,
        end_center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:,
        include_start_ring: true,
        include_end_ring: true
      )
        start_corners = rectangle_corners(
          center: start_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        end_corners = rectangle_corners(
          center: end_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        4.times do |index|
          next_index = (index + 1) % 4

          add_visible_edge(entities, start_corners[index], start_corners[next_index]) if include_start_ring
          add_visible_edge(entities, end_corners[index], end_corners[next_index]) if include_end_ring

          # Long outside corner lines only. These give the socket pieces their
          # clean duct-style border without adding the unwanted middle square.
          add_visible_edge(entities, start_corners[index], end_corners[index])
        end
      rescue => error
        puts "CrossBuilder.add_rectangular_prism_outline_edges failed: #{error.message}"
      end

    end
  end
end

# ===== Consolidated from: geometry/cross/shared_geometry.rb =====
module DuctExtension
  module Geometry
    module CrossBuilder
      def self.rectangle_corners(center:, width_axis:, height_axis:, half_width:, half_height:)
        PrimitiveHelpers.rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )
      end

      def self.add_visible_edge(entities, point_a, point_b)
        PrimitiveHelpers.add_visible_edge(
          entities,
          point_a,
          point_b,
          min_distance: 0.001,
          inclusive: false
        )
      end

      def self.edge_midpoint(edge)
        PrimitiveHelpers.edge_midpoint(edge)
      end

      def self.local_coords(point:, center:, forward_axis:, side_axis:, height_axis:)
        vector = center.vector_to(point)

        {
          forward: vector.dot(forward_axis),
          side: vector.dot(side_axis),
          height: vector.dot(height_axis)
        }
      rescue
        nil
      end

      def self.box_point(center, forward_axis, side_axis, height_axis, forward_amount, side_amount, height_amount)
        Geom::Point3d.new(
          center.x +
            forward_axis.x * forward_amount +
            side_axis.x * side_amount +
            height_axis.x * height_amount,

          center.y +
            forward_axis.y * forward_amount +
            side_axis.y * side_amount +
            height_axis.y * height_amount,

          center.z +
            forward_axis.z * forward_amount +
            side_axis.z * side_amount +
            height_axis.z * height_amount
        )
      end

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis)
      end

      private_class_method :build_round
      private_class_method :build_rectangular
      private_class_method :build_rectangular_socket
      private_class_method :add_oriented_box
      private_class_method :harden_all_rectangular_edges
      private_class_method :hide_rectangular_cross_seams
      private_class_method :add_rectangular_cross_boundary_edges
      private_class_method :add_rectangular_prism_outline_edges
      private_class_method :rectangle_corners
      private_class_method :add_visible_edge
      private_class_method :edge_midpoint
      private_class_method :local_coords
      private_class_method :box_point
      private_class_method :perpendicularized
      private_class_method :add_oval_hub
    end
  end
end
