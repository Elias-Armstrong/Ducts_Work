# ===== Consolidated from: services/geometry_cleanup_service.rb =====
module DuctExtension
  module Services
    module GeometryCleanupService
      def self.cleanup_group(group, shape: :round)
        return false unless group && group.valid?

        if shape.to_sym == :rectangular
          keep_rectangular_edges_visible(group)
        else
          soften_round_geometry(group)
        end

        true
      rescue => error
        puts "GeometryCleanupService.cleanup_group failed: #{error.message}"
        false
      end

      def self.soften_round_geometry(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = true
          edge.smooth = true
          edge.hidden = false
        end
      end

      def self.keep_rectangular_edges_visible(group)
        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = false
          edge.smooth = false
          edge.hidden = false
        end
      end

      private_class_method :soften_round_geometry
      private_class_method :keep_rectangular_edges_visible
    end
  end
end

# ===== Consolidated from: services/visual_style_service.rb =====
module DuctExtension
  module Services
    module VisualStyleService
      def self.capture_group_style(group)
        return nil unless group && group.valid?

        {
          material: group.material,
          layer: group.layer,
          hidden: group.hidden?,
          casts_shadows: group.casts_shadows?,
          receives_shadows: group.receives_shadows?
        }
      rescue => error
        puts "VisualStyleService.capture_group_style failed: #{error.message}"
        nil
      end

      def self.apply_group_style(group, style)
        return false unless group && group.valid?
        return false unless style

        group.material = style[:material] if style.key?(:material) && style[:material]
        group.layer = style[:layer] if style.key?(:layer) && style[:layer]

        group.hidden = style[:hidden] if style.key?(:hidden)

        if style.key?(:casts_shadows)
          group.casts_shadows = style[:casts_shadows]
        end

        if style.key?(:receives_shadows)
          group.receives_shadows = style[:receives_shadows]
        end

        apply_material_to_faces(group, group.material) if group.material

        true
      rescue => error
        puts "VisualStyleService.apply_group_style failed: #{error.message}"
        false
      end

      def self.apply_material_to_faces(group, material)
        return unless group && group.valid?
        return unless material

        group.entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?

          face.material = material
          face.back_material = material
        end
      rescue => error
        puts "VisualStyleService.apply_material_to_faces failed: #{error.message}"
      end

      private_class_method :apply_material_to_faces
    end
  end
end
