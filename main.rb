module DuctExtension
  module Model
  end

  module Geometry
  end

  module Services
  end

  module Tool
  end

  @model_networks ||= {}

  def self.network_for_model(model)
    @model_networks[model.guid] ||= Model::Network.new
  end
end

# ===== MODEL =====
require_relative 'model/port'
require_relative 'model/dimension_utils'
require_relative 'model/build_step'
require_relative 'model/duct_piece'
require_relative 'model/connection'
require_relative 'model/network'
require_relative 'model/spatial_port_index'

# ===== GEOMETRY =====
require_relative 'geometry/vector_math'
require_relative 'geometry/primitive_helpers'
require_relative 'geometry/mesh'
require_relative 'geometry/pipe_builder'
require_relative 'geometry/rectangular_frame'
require_relative 'geometry/rectangular_pipe_builder'
require_relative 'geometry/elbow_builder'
require_relative 'geometry/rectangular_elbow_builder'
require_relative 'geometry/tee_builder'
require_relative 'geometry/rectangular_tee_builder'
require_relative 'geometry/cross_builder'
require_relative 'geometry/wye_builder'
require_relative 'geometry/reducer_builder'
require_relative 'geometry/vent_builder'

# ===== SERVICES =====
require_relative 'services/piece_metadata_service'
require_relative 'services/network_rebuild_service'
require_relative 'services/network_clear_service'
require_relative 'services/geometry_cleanup_service'
require_relative 'services/visual_style_service'
require_relative 'services/snap_service'
require_relative 'services/connector_swing_service'
require_relative 'services/selection_resize_service'
require_relative 'services/selection_resize_fittings_patch'
require_relative 'services/route_planner'
require_relative 'services/geometry_executor'
require_relative 'services/tee_insert_service'
require_relative 'services/end_fitting_support'
require_relative 'services/pipe_connection_service'
require_relative 'services/end_tee_insert_service'
require_relative 'services/end_cross_insert_service'
require_relative 'services/end_wye_insert_service'
require_relative 'services/end_reducer_insert_service'
require_relative 'services/vent_insert_service'
require_relative 'services/port_to_port_route_service'
require_relative 'services/rectangular_endpoint_relief_service'

# ===== TOOL =====
require_relative 'tool/duct_tool'
require_relative 'tool/duct_tool_vent_patch'
require_relative 'tool/reducer_tool'

# ===== UI =====
require_relative 'ui/toolbar'
DuctExtension::Toolbar.create

module CustomDuctExtension
  unless @simple_duct_menu_created
    menu = UI.menu("Plugins").add_submenu("Simple Duct Extension")

    menu.add_item("Draw Orthogonal Duct") {
      Sketchup.active_model.select_tool(DuctExtension::Tool::DuctTool.new)
    }

    menu.add_item("Resize Selected Duct Pieces") {
      network = DuctExtension.network_for_model(Sketchup.active_model)

      DuctExtension::Services::SelectionResizeService.run(
        model: Sketchup.active_model,
        network: network
      )
    }

    menu.add_item("Add Increaser / Reducer") {
      Sketchup.active_model.select_tool(DuctExtension::Tool::ReducerTool.new)
    }

    menu.add_item("Clear Duct Data") {
      result = UI.messagebox(
        "This will clear all stored duct connection data from this model for performance purposes.\n\n" \
        "The 3D duct geometry will remain unchanged, but old ducts will no longer snap as editable duct pieces.\n\n" \
        "Continue?",
        MB_YESNO
      )

      if result == IDYES
        network = DuctExtension.network_for_model(Sketchup.active_model)

        DuctExtension::Services::NetworkClearService.clear_model_data(
          Sketchup.active_model,
          network
        )

        UI.messagebox("Duct data cleared. Geometry was left unchanged.")
      end
    }

    @simple_duct_menu_created = true
    file_loaded(__FILE__) unless file_loaded?(__FILE__)
  end
end
