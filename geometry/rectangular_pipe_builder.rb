module DuctExtension
  module Geometry
    module RectangularPipeBuilder
      OVERLAP_FACTOR = 0.0
      EPSILON = 0.000001

      def self.build_into(
        group,
        start_point,
        end_point,
        width,
        height,
        overlap_start: false,
        overlap_end: false,
        cap_start: true,
        cap_end: true,
        preferred_width_axis: nil,
        preferred_height_axis: nil,
        allow_relevel: true
      )
        return false unless group && group.valid?

        start_point = RectangularFrame.point3d(start_point)
        end_point = RectangularFrame.point3d(end_point)

        width = width.to_f
        height = height.to_f

        return false unless start_point && end_point
        return false if width <= 0.0 || height <= 0.0

        direction = start_point.vector_to(end_point)
        return false if direction.length <= EPSILON

        direction.normalize!

        largest = [width, height].max
        overlap = largest * OVERLAP_FACTOR

        mesh_start = overlap_start ? start_point.offset(direction.clone.reverse, overlap) : start_point
        mesh_end = overlap_end ? end_point.offset(direction, overlap) : end_point

        # Important:
        # This preserves the start-port frame when one exists. It only uses +Z to
        # flatten a free/new horizontal run. That prevents connected straight
        # ducts from swiveling independently.
        basis = RectangularFrame.stable_basis_for_axis(
          direction,
          width,
          height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: allow_relevel
        )

        return false unless basis

        start_corners = RectangularFrame.rectangle_corners_from_basis(
          mesh_start,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )

        end_corners = RectangularFrame.rectangle_corners_from_basis(
          mesh_end,
          basis[:width_axis],
          basis[:height_axis],
          width,
          height
        )

        return false if start_corners.empty? || end_corners.empty?

        entities = group.entities

        4.times do |index|
          next_index = (index + 1) % 4

          Mesh.add_quad(
            entities,
            start_corners[index],
            start_corners[next_index],
            end_corners[next_index],
            end_corners[index]
          )
        end

        if cap_start
          Mesh.add_face_safe(
            entities,
            start_corners.reverse,
            reverse_if_normal_against: direction.clone.reverse
          )
        end

        if cap_end
          Mesh.add_face_safe(
            entities,
            end_corners,
            reverse_if_normal_against: direction
          )
        end

        Mesh.keep_edges_visible(group)
        Mesh.apply_material_from_group(group)

        true
      rescue => error
        puts "RectangularPipeBuilder.build_into failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end
    end
  end
end

