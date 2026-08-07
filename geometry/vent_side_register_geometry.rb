module DuctExtension
  module Geometry
    module VentBuilder
      def self.build_side_register_into(
        group,
        center:,
        outward_axis:,
        duct_axis:,
        plate_width:,
        plate_height:,
        opening_width: nil,
        opening_height: nil,
        bumped_out: true,
        duct_diameter: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        outward_axis = RectangularFrame.normalized(outward_axis)
        duct_axis = RectangularFrame.normalized(duct_axis)

        plate_width = plate_width.to_f
        plate_height = plate_height.to_f
        opening_width = opening_width ? opening_width.to_f : plate_width * 0.72
        opening_height = opening_height ? opening_height.to_f : plate_height * 0.42
        duct_diameter = duct_diameter ? duct_diameter.to_f : nil

        return false unless center && outward_axis && duct_axis
        return false if plate_width <= 0.0 || plate_height <= 0.0
        return false if opening_width <= 0.0 || opening_height <= 0.0

        width_axis = perpendicularized(duct_axis, outward_axis)
        width_axis ||= fallback_perpendicular_axis(outward_axis)
        return false unless width_axis

        height_axis = outward_axis.cross(width_axis)
        return false if height_axis.length <= EPSILON
        height_axis.normalize!

        largest = [plate_width, plate_height].max

        bump_thickness =
          if bumped_out
            [largest * REGISTER_BUMP_FACTOR, 0.18].max
          else
            [largest * PLATE_THICKNESS_FACTOR, 0.06].max
          end

        # Shallow saddle/backing connector. It fills the daylight gap while
        # preserving the old front face appearance.
        build_register_saddle_connector(
          group,
          center: center,
          outward_axis: outward_axis,
          width_axis: width_axis,
          height_axis: height_axis,
          plate_width: plate_width,
          plate_height: plate_height,
          duct_diameter: duct_diameter,
          outer_offset: [bump_thickness * 0.28, 0.05].max
        )

        base_center = center.offset(outward_axis, 0.02)
        outer_center = center.offset(outward_axis, bump_thickness)

        build_plate_box(
          group,
          base_center: base_center,
          outer_center: outer_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: plate_width / 2.0,
          half_height: plate_height / 2.0
        )

        opening_center = outer_center.offset(outward_axis, SLOT_RECESS_FACTOR)

        add_black_opening_face(
          group,
          center: opening_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: opening_width / 2.0,
          half_height: opening_height / 2.0,
          normal: outward_axis
        )

        add_raised_frame_edges(
          group,
          center: outer_center.offset(outward_axis, SLOT_RECESS_FACTOR * 2.0),
          width_axis: width_axis,
          height_axis: height_axis,
          plate_half_width: plate_width / 2.0,
          plate_half_height: plate_height / 2.0,
          opening_half_width: opening_width / 2.0,
          opening_half_height: opening_height / 2.0
        )

        add_register_slats(
          group,
          center: opening_center.offset(outward_axis, SLOT_RECESS_FACTOR * 2.0),
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: opening_width / 2.0,
          half_height: opening_height / 2.0,
          count: 3
        )

        if bumped_out
          add_side_depth_edges(
            group,
            base_center: base_center,
            outer_center: outer_center,
            width_axis: width_axis,
            height_axis: height_axis,
            half_width: plate_width / 2.0,
            half_height: plate_height / 2.0
          )
        end

        add_screw_dots(
          group,
          center: outer_center.offset(outward_axis, SLOT_RECESS_FACTOR * 3.0),
          width_axis: width_axis,
          height_axis: height_axis,
          outward_axis: outward_axis,
          plate_half_width: plate_width / 2.0,
          plate_half_height: plate_height / 2.0,
          radius: largest * 0.025
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "VentBuilder.build_side_register_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_register_saddle_connector(
        group,
        center:,
        outward_axis:,
        width_axis:,
        height_axis:,
        plate_width:,
        plate_height:,
        duct_diameter: nil,
        outer_offset:
      )
        entities = group.entities

        half_width = plate_width.to_f / 2.0
        half_height = plate_height.to_f / 2.0

        outer_center = center.offset(outward_axis, outer_offset.to_f)

        outer = rectangle_corners(
          center: outer_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        return false if outer.empty?

        inner = []

        if duct_diameter && duct_diameter.to_f > 0.0
          radius = duct_diameter.to_f / 2.0

          max_depth = radius * REGISTER_SADDLE_MAX_DEPTH_FACTOR
          minimum_bite = [radius * REGISTER_SADDLE_MIN_BITE_FACTOR, REGISTER_SADDLE_MIN_DEPTH].max

          local_offsets = [
            [half_width, half_height],
            [-half_width, half_height],
            [-half_width, -half_height],
            [half_width, -half_height]
          ]

          local_offsets.each do |width_offset, height_offset|
            surface_point = center
                            .offset(width_axis, width_offset)
                            .offset(height_axis, height_offset)

            # For a round duct, height_axis is the circumferential direction
            # around the pipe. Pull the outer corners inward just enough to
            # visually meet the pipe curvature.
            clamped_height = [[height_offset.abs, radius * 0.86].min, 0.0].max
            under_root = [radius * radius - clamped_height * clamped_height, 0.0].max
            sagitta = radius - Math.sqrt(under_root)

            depth = sagitta + minimum_bite
            depth = [[depth, minimum_bite].max, max_depth].min

            inner << surface_point.offset(outward_axis.clone.reverse, depth)
          end
        else
          # Rectangular duct or unknown duct type: use a modest straight bite.
          # Enough to fill gaps, not enough to become a huge visible block.
          depth = [plate_height.to_f * 0.18, 0.10].max

          inner_center = center.offset(outward_axis.clone.reverse, depth)

          inner = rectangle_corners(
            center: inner_center,
            width_axis: width_axis,
            height_axis: height_axis,
            half_width: half_width,
            half_height: half_height
          )
        end

        return false if inner.empty?

        Mesh.add_face_safe(entities, outer)
        Mesh.add_face_safe(entities, inner.reverse)

        4.times do |index|
          next_index = (index + 1) % 4

          Mesh.add_quad(
            entities,
            inner[index],
            inner[next_index],
            outer[next_index],
            outer[index]
          )
        end

        add_ring_edges(entities, outer)
        add_ring_edges(entities, inner)

        true
      rescue => error
        puts "VentBuilder.build_register_saddle_connector failed: #{error.message}"
        false
      end

    end
  end
end
