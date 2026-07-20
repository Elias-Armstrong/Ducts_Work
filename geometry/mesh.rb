module DuctExtension
  module Geometry
    module Mesh
      EPSILON = 0.000001

      def self.add_face_safe(entities, points, reverse_if_normal_against: nil)
        clean_points = Array(points).compact
        return nil if clean_points.length < 3

        face = entities.add_face(clean_points)
        return nil unless face

        if reverse_if_normal_against
          normal = normalized(reverse_if_normal_against)

          if normal && face.normal.dot(normal) < 0
            face.reverse!
          end
        end

        face
      rescue => error
        puts "Mesh.add_face_safe failed: #{error.message}"
        nil
      end

      def self.add_quad(entities, p1, p2, p3, p4)
        face = add_face_safe(entities, [p1, p2, p3, p4])

        unless face
          # SketchUp can reject slightly non-planar quads. Fall back to two triangles.
          add_face_safe(entities, [p1, p2, p3])
          add_face_safe(entities, [p1, p3, p4])
        end
      end

      def self.soft_smooth_edges(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = true
          edge.smooth = true
        end
      rescue => error
        puts "Mesh.soft_smooth_edges failed: #{error.message}"
      end

      def self.soft_smooth_round_edges(group)
        soft_smooth_edges(group)
      end

      def self.keep_edges_visible(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.hidden = false
        end
      rescue => error
        puts "Mesh.keep_edges_visible failed: #{error.message}"
      end

      def self.apply_material_from_group(group)
        return unless group && group.valid?
        return unless group.material

        material = group.material

        group.entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?

          face.material = material
          face.back_material = material
        end
      rescue => error
        puts "Mesh.apply_material_from_group failed: #{error.message}"
      end

      def self.normalized(vector)
        VectorMath.normalized(vector, epsilon: EPSILON)
      end
    end
  end
end
