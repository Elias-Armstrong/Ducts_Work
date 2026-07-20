module DuctExtension
  module Geometry
    module RectangularElbowBuilder
      SEGMENTS = 16
      EPSILON = 0.000001

      def self.build_into(
        group,
        start_point,
        entry_vector,
        exit_vector,
        width,
        height,
        bend_radius,
        cap_start: false,
        cap_end: false,
        preferred_width_axis: nil,
        preferred_height_axis: nil
      )
        return false unless group && group.valid?

        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)

        width = width.to_f
        height = height.to_f
        bend_radius = bend_radius.to_f

        return false unless start_point && entry_vector && exit_vector
        return false if width <= 0.0 || height <= 0.0 || bend_radius <= 0.0

        arc = ElbowBuilder.send(
          :arc_data,
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius
        )

        return false unless arc

        # Elbows must inherit their start-port frame. They should not relevel or
        # independently choose world X/Y roll.
        start_basis = RectangularFrame.stable_basis_for_axis(
          entry_vector,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )

        return false unless start_basis

        sections = []

        (SEGMENTS + 1).times do |index|
          t = index.to_f / SEGMENTS.to_f
          theta = arc[:angle] * t

          rotation = Geom::Transformation.rotation(
            arc[:center],
            arc[:normal],
            theta
          )

          section_center = start_point.transform(rotation)
          section_axis = entry_vector.transform(rotation)
          section_width_axis = start_basis[:width_axis].transform(rotation)
          section_height_axis = start_basis[:height_axis].transform(rotation)

          section_axis.normalize!
          section_width_axis.normalize!
          section_height_axis.normalize!

          # Preserve transported frame exactly through the bend.
          section_basis = RectangularFrame.basis_for_axis(
            section_axis,
            preferred_width_axis: section_width_axis,
            preferred_height_axis: section_height_axis
          )

          return false unless section_basis

          corners = RectangularFrame.rectangle_corners_from_basis(
            section_center,
            section_basis[:width_axis],
            section_basis[:height_axis],
            width,
            height
          )

          return false if corners.empty?

          sections << {
            center: section_center,
            axis: section_axis,
            width_axis: section_basis[:width_axis],
            height_axis: section_basis[:height_axis],
            corners: corners
          }
        end

        entities = group.entities

        SEGMENTS.times do |section_index|
          current = sections[section_index][:corners]
          nxt = sections[section_index + 1][:corners]

          4.times do |corner_index|
            next_corner_index = (corner_index + 1) % 4

            Mesh.add_quad(
              entities,
              current[corner_index],
              current[next_corner_index],
              nxt[next_corner_index],
              nxt[corner_index]
            )
          end
        end

        if cap_start
          Mesh.add_face_safe(
            entities,
            sections.first[:corners].reverse,
            reverse_if_normal_against: entry_vector.clone.reverse
          )
        end

        if cap_end
          Mesh.add_face_safe(
            entities,
            sections.last[:corners],
            reverse_if_normal_against: exit_vector
          )
        end

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "RectangularElbowBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.exit_point(start_point, entry_vector, exit_vector, bend_radius)
        ElbowBuilder.exit_point(start_point, entry_vector, exit_vector, bend_radius)
      end

      def self.exit_basis(
        start_point:,
        entry_vector:,
        exit_vector:,
        bend_radius:,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        width: nil,
        height: nil,
        allow_relevel: false
      )
        start_point = RectangularFrame.point3d(start_point)
        entry_vector = RectangularFrame.normalized(entry_vector)
        exit_vector = RectangularFrame.normalized(exit_vector)

        width = width.to_f
        height = height.to_f
        bend_radius = bend_radius.to_f

        return nil unless start_point && entry_vector && exit_vector
        return nil if width <= 0.0 || height <= 0.0 || bend_radius <= 0.0

        arc = ElbowBuilder.send(
          :arc_data,
          start_point: start_point,
          entry_vector: entry_vector,
          exit_vector: exit_vector,
          bend_radius: bend_radius
        )

        return nil unless arc

        start_basis = RectangularFrame.stable_basis_for_axis(
          entry_vector,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )

        return nil unless start_basis

        rotation = Geom::Transformation.rotation(
          arc[:center],
          arc[:normal],
          arc[:angle]
        )

        width_axis = start_basis[:width_axis].transform(rotation)
        height_axis = start_basis[:height_axis].transform(rotation)

        width_axis.normalize!
        height_axis.normalize!

        # Return the transported rectangular frame. The next connected straight
        # piece should inherit this exact exit frame.
        RectangularFrame.basis_for_axis(
          exit_vector,
          preferred_width_axis: width_axis,
          preferred_height_axis: height_axis
        )
      rescue => error
        puts "RectangularElbowBuilder.exit_basis failed: #{error.message}"
        nil
      end
    end
  end
end
