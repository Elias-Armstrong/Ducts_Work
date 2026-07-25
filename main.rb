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
require_relative 'model/port'
require_relative 'model/build_step'
require_relative 'model/duct_piece'
require_relative 'model/connection'
require_relative 'model/network'
require_relative 'model/spatial_port_index'

# ===== GEOMETRY =====
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
require_relative 'geometry/mixed_transition_builder'
require_relative 'geometry/reducer_builder'
require_relative 'geometry/vent_builder'

# ===== SERVICES =====
require_relative 'services/piece_metadata_service'
require_relative 'services/network_rebuild_service'
require_relative 'services/network_validator'
require_relative 'services/model_operation'
require_relative 'services/port_cap_service'
require_relative 'services/network_clear_service'
require_relative 'services/geometry_cleanup_service'
require_relative 'services/visual_style_service'
require_relative 'services/snap_service'
require_relative 'services/fitting_rebuild_support'
require_relative 'services/fitting_resize_rebuilder'
require_relative 'services/rectangular_fitting_swing_rebuilder'
require_relative 'services/fitting_rebuild_service'
require_relative 'services/connector_swing_service'
require_relative 'services/selection_resize_planner'
require_relative 'services/selection_resize_layout_service'
require_relative 'services/selection_piece_resize_service'
require_relative 'services/selection_resize_service'
require_relative 'services/route_planner'
require_relative 'services/geometry_executor'
require_relative 'services/branch_transition_service'
require_relative 'services/branch_size_prompt'
require_relative 'services/tee_insert_service'
require_relative 'services/end_fitting_support'
require_relative 'services/tee_placement_calculator'
require_relative 'services/pipe_connection_service'
require_relative 'services/end_tee_insert_service'
require_relative 'services/end_cross_insert_service'
require_relative 'services/end_wye_insert_service'
require_relative 'services/end_reducer_insert_service'
require_relative 'services/vent_insert_service'
require_relative 'services/routing/route_context'
require_relative 'services/routing/route_math'
require_relative 'services/routing/strategies/direct_strategy'
require_relative 'services/routing/strategies/two_terminal_elbow_strategy'
require_relative 'services/routing/strategies/one_elbow_strategy'
require_relative 'services/routing/strategies/dogleg_strategy'
require_relative 'services/routing/strategy_pipeline'
require_relative 'services/port_to_port_route_service'

# ===== TOOL =====
require_relative 'tool/input_helpers'
require_relative 'tool/reducer_prompt'
require_relative 'tool/duct_tool_menu'
require_relative 'tool/duct_tool_typed_length'
require_relative 'tool/duct_tool_vents'
require_relative 'tool/duct_tool_fittings'
require_relative 'tool/duct_tool_navigation'
require_relative 'tool/duct_tool_routing_preview'
require_relative 'tool/duct_tool_settings'
require_relative 'tool/duct_tool'
require_relative 'tool/reducer_tool'

# ===== UI =====
require_relative 'ui/actions'
require_relative 'ui/toolbar'
DuctExtension::Toolbar.create

module CustomDuctExtension
  unless @simple_duct_menu_created
    menu = UI.menu("Plugins").add_submenu("Simple Duct Extension")

    menu.add_item("Draw Orthogonal Duct") { DuctExtension::UIActions.draw_duct }
    menu.add_item("Resize Selected Duct Pieces") { DuctExtension::UIActions.resize_selection }
    menu.add_item("Add Increaser / Reducer") { DuctExtension::UIActions.add_reducer }
    menu.add_item("Clear Duct Data") { DuctExtension::UIActions.clear_duct_data }

    @simple_duct_menu_created = true
    file_loaded(__FILE__) unless file_loaded?(__FILE__)
  end
end
