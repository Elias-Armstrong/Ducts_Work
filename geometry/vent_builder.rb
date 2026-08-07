# ===== Consolidated from: geometry/vent_builder.rb =====
module DuctExtension
  module Geometry
    module VentBuilder
      EPSILON = 0.000001

      ROUND_SEGMENTS = 40
      GRILLE_RINGS = 5
      GRILLE_SPOKES = 12

      PLATE_THICKNESS_FACTOR = 0.045
      SLOT_RECESS_FACTOR = 0.018

      END_COVER_OVERSIZE_FACTOR = 1.22
      END_COVER_THICKNESS_FACTOR = 0.10
      END_COVER_DOME_FACTOR = 0.08

      REGISTER_BUMP_FACTOR = 0.12

      # Register connector tuning.
      #
      # Goal:
      # - Keep the nice previous front-face register aesthetic.
      # - Fill the visible gap between register and pipe.
      # - Do NOT punch through the far side of round duct.
      #
      # This builds a shallow saddle connector behind the register. On round
      # ducts, the hidden back corners are pulled inward according to pipe
      # curvature, then clamped so the connector only bites into the near side.
      REGISTER_SADDLE_MIN_BITE_FACTOR = 0.055
      REGISTER_SADDLE_MAX_DEPTH_FACTOR = 0.42
      REGISTER_SADDLE_MIN_DEPTH = 0.08

    end
  end
end

# ===== Consolidated from: geometry/vent/end_cover_geometry.rb =====
module DuctExtension
  module Geometry
    module VentBuilder
      def self.build_round_end_cover_into(
        group,
        center:,
        axis:,
        duct_diameter:,
        cover_diameter: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        axis = RectangularFrame.normalized(axis)

        duct_diameter = duct_diameter.to_f
        cover_diameter = cover_diameter ? cover_diameter.to_f : duct_diameter * END_COVER_OVERSIZE_FACTOR

        return false unless center && axis
        return false if duct_diameter <= 0.0 || cover_diameter <= 0.0

        radius = cover_diameter / 2.0
        thickness = [cover_diameter * END_COVER_THICKNESS_FACTOR, 0.12].max
        dome = cover_diameter * END_COVER_DOME_FACTOR

        axis_a, axis_b = circle_basis(axis)
        return false unless axis_a && axis_b

        entities = group.entities

        back_center = center.offset(axis, thickness * 0.10)
        face_center = center.offset(axis, thickness + dome)

        outer_back = ring_points(back_center, axis_a, axis_b, radius * 0.96, ROUND_SEGMENTS)
        outer_face = ring_points(face_center, axis_a, axis_b, radius, ROUND_SEGMENTS)

        Mesh.add_face_safe(entities, outer_face, reverse_if_normal_against: axis)
        Mesh.add_face_safe(entities, outer_back.reverse, reverse_if_normal_against: axis.clone.reverse)

        ROUND_SEGMENTS.times do |index|
          next_index = (index + 1) % ROUND_SEGMENTS

          Mesh.add_quad(
            entities,
            outer_back[index],
            outer_back[next_index],
            outer_face[next_index],
            outer_face[index]
          )
        end

        add_ring_edges(entities, outer_face)
        add_ring_edges(entities, outer_back)

        add_circular_grille(
          group,
          center: face_center.offset(axis, 0.02),
          axis: axis,
          radius: radius * 0.78,
          axis_a: axis_a,
          axis_b: axis_b
        )

        add_center_disc(
          group,
          center: face_center.offset(axis, 0.03),
          axis: axis,
          radius: radius * 0.13
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "VentBuilder.build_round_end_cover_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_rectangular_end_cover_into(
        group,
        center:,
        axis:,
        width:,
        height:,
        width_axis:,
        height_axis:,
        cover_width: nil,
        cover_height: nil
      )
        return false unless group && group.valid?

        center = RectangularFrame.point3d(center)
        axis = RectangularFrame.normalized(axis)
        width_axis = RectangularFrame.normalized(width_axis)
        height_axis = RectangularFrame.normalized(height_axis)

        width = width.to_f
        height = height.to_f
        cover_width = cover_width ? cover_width.to_f : width * END_COVER_OVERSIZE_FACTOR
        cover_height = cover_height ? cover_height.to_f : height * END_COVER_OVERSIZE_FACTOR

        return false unless center && axis && width_axis && height_axis
        return false if width <= 0.0 || height <= 0.0
        return false if cover_width <= 0.0 || cover_height <= 0.0

        width_axis = perpendicularized(width_axis, axis)
        width_axis ||= fallback_perpendicular_axis(axis)
        return false unless width_axis

        height_axis = axis.cross(width_axis)
        return false if height_axis.length <= EPSILON
        height_axis.normalize!

        largest = [cover_width, cover_height].max
        thickness = [largest * END_COVER_THICKNESS_FACTOR, 0.12].max

        back_center = center.offset(axis, thickness * 0.10)
        face_center = center.offset(axis, thickness)

        build_plate_box(
          group,
          base_center: back_center,
          outer_center: face_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: cover_width / 2.0,
          half_height: cover_height / 2.0
        )

        add_rectangular_grille(
          group,
          center: face_center.offset(axis, 0.025),
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: cover_width * 0.38,
          half_height: cover_height * 0.38
        )

        add_screw_dots(
          group,
          center: face_center.offset(axis, 0.035),
          width_axis: width_axis,
          height_axis: height_axis,
          outward_axis: axis,
          plate_half_width: cover_width / 2.0,
          plate_half_height: cover_height / 2.0,
          radius: largest * 0.025
        )

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "VentBuilder.build_rectangular_end_cover_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.build_plate_box(
        group,
        base_center:,
        outer_center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:
      )
        entities = group.entities

        base = rectangle_corners(
          center: base_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        outer = rectangle_corners(
          center: outer_center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        return false if base.empty? || outer.empty?

        Mesh.add_face_safe(entities, outer)
        Mesh.add_face_safe(entities, base.reverse)

        4.times do |index|
          next_index = (index + 1) % 4

          Mesh.add_quad(
            entities,
            base[index],
            base[next_index],
            outer[next_index],
            outer[index]
          )
        end

        add_ring_edges(entities, outer)
        add_ring_edges(entities, base)

        true
      rescue => error
        puts "VentBuilder.build_plate_box failed: #{error.message}"
        false
      end

    end
  end
end
