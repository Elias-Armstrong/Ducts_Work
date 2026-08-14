module DuctExtension
  module Model
  end

  module Geometry
  end

  module Services
  end

  module Tool
  end

  module Catalog
  end

  @model_networks ||= {}
  @network_validation_enabled = false if @network_validation_enabled.nil?

  def self.network_validation_enabled?
    !!@network_validation_enabled
  end

  def self.network_validation_enabled=(value)
    @network_validation_enabled = !!value
  end

  def self.network_for_model(model)
    @model_networks[model.guid] ||= Model::Network.new
  end
end

# ===== SHARED FOUNDATIONS =====
require_relative 'geometry/vector_math'

# ===== MODEL =====
require_relative 'model/duct_dimensions'
require_relative 'model/topology'
require_relative 'model/network'

# ===== CATALOGS =====
require_relative 'catalog/master_flow'
require_relative 'catalog/manager'

# ===== GEOMETRY =====
require_relative 'geometry/primitive_helpers'
require_relative 'geometry/mesh'
require_relative 'geometry/pipe_builder'
require_relative 'geometry/rectangular_frame'
require_relative 'geometry/rectangular_frame_transport'
require_relative 'geometry/rectangular_pipe_builder'
require_relative 'geometry/elbow_builder'
require_relative 'geometry/rectangular_elbow_builder'
require_relative 'geometry/tee_builder'
require_relative 'geometry/cross_builder'
require_relative 'geometry/cross_rectangular_geometry'
require_relative 'geometry/wye_builder'
require_relative 'geometry/wye_round_geometry'
require_relative 'geometry/wye_rectangular_geometry'
require_relative 'geometry/mixed_transition_builder'
require_relative 'geometry/reducer_builder'
require_relative 'geometry/vent_builder'
require_relative 'geometry/vent_side_register_geometry'
require_relative 'geometry/vent_detail_geometry'
require_relative 'catalog/master_flow_geometry'

# ===== CORE SERVICES =====
require_relative 'services/network_persistence_service'
require_relative 'services/network_validator'
require_relative 'services/model_operation'
require_relative 'services/port_cap_service'
require_relative 'services/visual_style_service'
require_relative 'services/snap_service'

# ===== FITTINGS / TRANSITIONS =====
require_relative 'services/fitting_rebuild_service'
require_relative 'services/fitting_resize_rebuilder'
require_relative 'services/rectangular_fitting_swing_rebuilder'
require_relative 'services/connector_swing_service'
require_relative 'services/transition_service'
require_relative 'services/end_fitting_support'
require_relative 'services/tee_insert_service'
require_relative 'services/inline_wye_insert_service'
require_relative 'services/tee_placement_calculator'
require_relative 'services/end_junction_insert_service'
require_relative 'services/end_wye_insert_service'
require_relative 'services/vent_insert_service'

# ===== SELECTION RESIZE =====
require_relative 'services/selection_resize_service'
require_relative 'services/selection_resize_geometry'

# ===== ROUTING =====
require_relative 'routing/core'
require_relative 'routing/strategies'
require_relative 'routing/route_planner'
require_relative 'routing/geometry_executor'
require_relative 'routing/connection_service'

# ===== TOOL =====
# IMPORTANT: Keep this tool composition on the P8/661b62b baseline that has
# now been runtime-confirmed to receive SketchUp's right-click getMenu callback.
require_relative 'tool/duct_tool_interaction'
require_relative 'tool/duct_tool_components'
require_relative 'tool/duct_tool_navigation'
require_relative 'tool/duct_tool_preview'
require_relative 'tool/duct_tool'
require_relative 'tool/reducer_tool'

# ===== UI =====
require_relative 'ui/ui'
DuctExtension::Toolbar.create

module CustomDuctExtension
  unless @simple_duct_menu_created
    menu = UI.menu("Extensions").add_submenu("Simple Duct Extension")

    catalog_menu = menu.add_submenu("Catalog")
    catalog_menu.add_item("Set Catalog...") { DuctExtension::UIActions.set_catalog }
    catalog_menu.add_separator
    catalog_menu.add_item("Browse Active Catalog...") { DuctExtension::UIActions.browse_catalog }
    catalog_menu.add_item("Current Size / Availability...") { DuctExtension::UIActions.current_catalog_options }
    catalog_menu.add_item("Choose Current Duct / Elbow Products...") { DuctExtension::UIActions.choose_catalog_products }

    menu.add_separator
    menu.add_item("Draw Orthogonal Duct") { DuctExtension::UIActions.draw_duct }
    menu.add_item("Resize Selected Duct Pieces") { DuctExtension::UIActions.resize_selection }
    menu.add_item("Add Increaser / Reducer") { DuctExtension::UIActions.add_reducer }
    menu.add_item("Clear Duct Data") { DuctExtension::UIActions.clear_duct_data }

    @simple_duct_menu_created = true
    file_loaded(__FILE__) unless file_loaded?(__FILE__)
  end
end
