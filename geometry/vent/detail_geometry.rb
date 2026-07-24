module DuctExtension
  module Geometry
    module VentBuilder
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
