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

      def self.add_circular_grille(group, center:, axis:, radius:, axis_a:, axis_b:)
        entities = group.entities

        GRILLE_RINGS.times do |ring_index|
          ring_radius = radius * (ring_index + 1).to_f / GRILLE_RINGS.to_f

          add_ring_edges(
            entities,
            ring_points(center, axis_a, axis_b, ring_radius, ROUND_SEGMENTS)
          )
        end

        GRILLE_SPOKES.times do |index|
          angle = Math::PI * 2.0 * index.to_f / GRILLE_SPOKES.to_f

          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )

          radial.normalize!

          inner = center.offset(radial, radius * 0.15)
          outer = center.offset(radial, radius)

          add_visible_edge(entities, inner, outer)
        end
      rescue => error
        puts "VentBuilder.add_circular_grille failed: #{error.message}"
      end

      def self.add_rectangular_grille(group, center:, width_axis:, height_axis:, half_width:, half_height:)
        entities = group.entities

        add_ring_edges(
          entities,
          rectangle_corners(
            center: center,
            width_axis: width_axis,
            height_axis: height_axis,
            half_width: half_width,
            half_height: half_height
          )
        )

        5.times do |index|
          ratio = -0.66 + index * 0.33
          offset = half_height * ratio

          a = center.offset(height_axis, offset).offset(width_axis.clone.reverse, half_width)
          b = center.offset(height_axis, offset).offset(width_axis, half_width)

          add_visible_edge(entities, a, b)
        end

        5.times do |index|
          ratio = -0.66 + index * 0.33
          offset = half_width * ratio

          a = center.offset(width_axis, offset).offset(height_axis.clone.reverse, half_height)
          b = center.offset(width_axis, offset).offset(height_axis, half_height)

          add_visible_edge(entities, a, b)
        end
      rescue => error
        puts "VentBuilder.add_rectangular_grille failed: #{error.message}"
      end

      def self.add_register_slats(group, center:, width_axis:, height_axis:, half_width:, half_height:, count:)
        entities = group.entities

        count.times do |index|
          ratio = (index + 1).to_f / (count + 1).to_f
          y = -half_height + ratio * half_height * 2.0

          a = center.offset(height_axis, y).offset(width_axis.clone.reverse, half_width * 0.88)
          b = center.offset(height_axis, y).offset(width_axis, half_width * 0.88)

          add_visible_edge(entities, a, b)
        end
      rescue
        nil
      end

      def self.add_raised_frame_edges(
        group,
        center:,
        width_axis:,
        height_axis:,
        plate_half_width:,
        plate_half_height:,
        opening_half_width:,
        opening_half_height:
      )
        entities = group.entities

        outer = rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: plate_half_width,
          half_height: plate_half_height
        )

        inner = rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: opening_half_width,
          half_height: opening_half_height
        )

        add_ring_edges(entities, outer)
        add_ring_edges(entities, inner)

        4.times do |index|
          add_visible_edge(entities, outer[index], inner[index])
        end
      rescue => error
        puts "VentBuilder.add_raised_frame_edges failed: #{error.message}"
      end

      def self.add_side_depth_edges(
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

        4.times do |index|
          add_visible_edge(entities, base[index], outer[index])
        end
      rescue
        nil
      end

      def self.add_screw_dots(
        group,
        center:,
        width_axis:,
        height_axis:,
        outward_axis:,
        plate_half_width:,
        plate_half_height:,
        radius:
      )
        screw_positions = [
          center.offset(width_axis, plate_half_width * 0.78).offset(height_axis, plate_half_height * 0.68),
          center.offset(width_axis.clone.reverse, plate_half_width * 0.78).offset(height_axis, plate_half_height * 0.68),
          center.offset(width_axis.clone.reverse, plate_half_width * 0.78).offset(height_axis.clone.reverse, plate_half_height * 0.68),
          center.offset(width_axis, plate_half_width * 0.78).offset(height_axis.clone.reverse, plate_half_height * 0.68)
        ]

        screw_positions.each do |point|
          add_small_disc(
            group,
            center: point,
            axis: outward_axis,
            radius: radius
          )
        end
      rescue => error
        puts "VentBuilder.add_screw_dots failed: #{error.message}"
      end

      def self.add_black_opening_face(
        group,
        center:,
        width_axis:,
        height_axis:,
        half_width:,
        half_height:,
        normal:
      )
        entities = group.entities

        points = rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height
        )

        face = Mesh.add_face_safe(
          entities,
          points,
          reverse_if_normal_against: normal
        )

        apply_black_material(group, face)
      rescue => error
        puts "VentBuilder.add_black_opening_face failed: #{error.message}"
      end

      def self.add_center_disc(group, center:, axis:, radius:)
        add_small_disc(
          group,
          center: center,
          axis: axis,
          radius: radius
        )
      end

      def self.add_small_disc(group, center:, axis:, radius:)
        axis_a, axis_b = circle_basis(axis)
        return unless axis_a && axis_b

        points = ring_points(center, axis_a, axis_b, radius, 16)

        face = Mesh.add_face_safe(
          group.entities,
          points,
          reverse_if_normal_against: axis
        )

        apply_dark_gray_material(group, face)
      rescue
        nil
      end

      def self.apply_black_material(group, face)
        return unless group && group.valid?
        return unless face && face.valid?

        material = black_material(group.model)
        face.material = material
        face.back_material = material
      rescue
        nil
      end

      def self.apply_dark_gray_material(group, face)
        return unless group && group.valid?
        return unless face && face.valid?

        material = dark_gray_material(group.model)
        face.material = material
        face.back_material = material
      rescue
        nil
      end

      def self.black_material(model)
        material = model.materials["Duct Vent Black"]

        unless material
          material = model.materials.add("Duct Vent Black")
          material.color = Sketchup::Color.new(6, 6, 6)
        end

        material
      end

      def self.dark_gray_material(model)
        material = model.materials["Duct Vent Screw Dark Gray"]

        unless material
          material = model.materials.add("Duct Vent Screw Dark Gray")
          material.color = Sketchup::Color.new(45, 45, 45)
        end

        material
      end

      def self.rectangle_corners(center:, width_axis:, height_axis:, half_width:, half_height:)
        PrimitiveHelpers.rectangle_corners(
          center: center,
          width_axis: width_axis,
          height_axis: height_axis,
          half_width: half_width,
          half_height: half_height,
          normalize_axes: true
        )
      end

      def self.circle_basis(axis)
        axis = RectangularFrame.normalized(axis)
        return nil unless axis

        reference =
          if axis.dot(Geom::Vector3d.new(0, 0, 1)).abs < 0.95
            Geom::Vector3d.new(0, 0, 1)
          else
            Geom::Vector3d.new(1, 0, 0)
          end

        axis_a = axis.cross(reference)
        return nil if axis_a.length <= EPSILON
        axis_a.normalize!

        axis_b = axis.cross(axis_a)
        return nil if axis_b.length <= EPSILON
        axis_b.normalize!

        [axis_a, axis_b]
      rescue
        nil
      end

      def self.ring_points(center, axis_a, axis_b, radius, segments)
        points = []

        segments.times do |index|
          angle = Math::PI * 2.0 * index.to_f / segments.to_f

          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )

          radial.normalize!

          points << center.offset(radial, radius)
        end

        points
      rescue
        []
      end

      def self.add_ring_edges(entities, points)
        points = Array(points)
        return if points.length < 3

        points.length.times do |index|
          add_visible_edge(
            entities,
            points[index],
            points[(index + 1) % points.length]
          )
        end
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

      def self.perpendicularized(vector, axis)
        VectorMath.perpendicularized(vector, axis, epsilon: EPSILON)
      end

      def self.fallback_perpendicular_axis(axis)
        VectorMath.fallback_perpendicular_axis(axis, epsilon: EPSILON)
      end

      private_class_method :build_register_saddle_connector
      private_class_method :build_plate_box
      private_class_method :add_circular_grille
      private_class_method :add_rectangular_grille
      private_class_method :add_register_slats
      private_class_method :add_raised_frame_edges
      private_class_method :add_side_depth_edges
      private_class_method :add_screw_dots
      private_class_method :add_black_opening_face
      private_class_method :add_center_disc
      private_class_method :add_small_disc
      private_class_method :apply_black_material
      private_class_method :apply_dark_gray_material
      private_class_method :black_material
      private_class_method :dark_gray_material
      private_class_method :rectangle_corners
      private_class_method :circle_basis
      private_class_method :ring_points
      private_class_method :add_ring_edges
      private_class_method :add_visible_edge
      private_class_method :perpendicularized
      private_class_method :fallback_perpendicular_axis
    end
  end
end
