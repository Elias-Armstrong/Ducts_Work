# ===== Consolidated from: ui/actions.rb =====
module DuctExtension
  module UIActions
    module_function

    def set_catalog
      model = Sketchup.active_model
      key = Catalog::Manager.prompt_set_catalog(model)

      # Switching construction modes should leave the user inside Simple Duct,
      # not silently return them to SketchUp's Select tool. This also guarantees
      # that Tool#getMenu owns the next right-click immediately after a mode change.
      model.select_tool(Tool::DuctTool.new) if key
      key
    end

    def browse_catalog
      Catalog::Manager.show_catalog_browser(Sketchup.active_model)
    end

    def active_duct_tool
      tool = Tool::DuctTool.active_instance if Tool::DuctTool.respond_to?(:active_instance)
      tool.is_a?(Tool::DuctTool) ? tool : nil
    rescue
      nil
    end

    def use_base_catalog
      model = Sketchup.active_model
      Catalog::Manager.set_active(model, Catalog::Manager::BASE_KEY)
      ::UI.messagebox("Base / Generic mode enabled. New pieces use the original free-form Simple Duct workflow.")
      model.select_tool(Tool::DuctTool.new)
      true
    rescue => error
      puts "UIActions.use_base_catalog failed: #{error.message}"
      false
    end

    def use_master_flow_catalog
      model = Sketchup.active_model
      Catalog::Manager.set_active(model, Catalog::Manager::MASTER_FLOW_KEY)
      ::UI.messagebox("Master Flow catalog mode enabled. New pieces are restricted to loaded Master Flow products.")
      model.select_tool(Tool::DuctTool.new)
      true
    rescue => error
      puts "UIActions.use_master_flow_catalog failed: #{error.message}"
      false
    end

    def current_catalog_options
      tool = active_duct_tool
      return tool.show_catalog_options_from_ui if tool

      model = Sketchup.active_model
      dimensions = nil
      begin
        network = Services::NetworkRebuildService.rebuild(model)
        selected_groups = model.selection.to_a
        piece = network.pieces.find { |candidate| candidate && selected_groups.include?(candidate.group) }
        dimensions = Model::Port.dimensions_from_params({}, piece.ports.first) if piece && piece.ports && piece.ports.first
      rescue => error
        puts "UIActions.current_catalog_options selection lookup failed: #{error.message}"
      end

      Catalog::Manager.show_catalog_browser(model, dimensions: dimensions)
    end

    def choose_catalog_products
      tool = active_duct_tool
      return tool.choose_catalog_products_from_ui if tool

      draw_duct
    end

    def activate_duct_component(mode)
      tool = active_duct_tool
      if tool
        tool.set_fitting_mode_from_ui(mode)
      else
        Sketchup.active_model.select_tool(
          Tool::DuctTool.new(initial_fitting_mode: mode, prompt_settings: false)
        )
      end
      true
    rescue => error
      puts "UIActions.activate_duct_component failed: #{error.message}"
      false
    end

    def add_tee
      activate_duct_component(:tee)
    end

    def add_end_tee
      activate_duct_component(:end_tee)
    end

    def add_end_wye
      activate_duct_component(:end_wye)
    end

    def add_end_cross
      activate_duct_component(:end_cross)
    end

    def add_end_reducer
      activate_duct_component(:end_reducer)
    end

    def add_end_cover
      activate_duct_component(:vent)
    end

    # Re-enter Simple Duct without opening the setup prompt. This is useful
    # after orbit/select operations or whenever SketchUp has switched back to a
    # native tool.
    def resume_duct_tool
      Sketchup.active_model.select_tool(
        Tool::DuctTool.new(prompt_settings: false)
      )
      Sketchup.status_text = "Simple Duct tool resumed. Right-click for Simple Duct controls."
      true
    rescue => error
      puts "UIActions.resume_duct_tool failed: #{error.message}"
      false
    end

    # Compact native fallback for environments where SketchUp suppresses the
    # application-level context handler.
    def quick_menu
      catalog_name = Catalog::Manager.active_name(Sketchup.active_model)

      labels = [
        "Resume / Activate Duct Tool",
        "Draw Duct (open settings)",
        "Set Catalog...",
        "Use Base / Generic",
        "Use Master Flow",
        "Browse Active Catalog...",
        "Current Size / Availability...",
        "Choose Duct / Elbow Products...",
        "Add Tee",
        "End Tee",
        "End Wye",
        "End Reducer / Converter",
        "End Cover / Vent",
        "Menu Diagnostics..."
      ]

      result = ::UI.inputbox(
        ["Command:"],
        [labels.first],
        [labels.join("|")],
        "Simple Duct — #{catalog_name}"
      )
      return false unless result

      case result[0].to_s
      when labels[0]  then resume_duct_tool
      when labels[1]  then draw_duct
      when labels[2]  then set_catalog
      when labels[3]  then use_base_catalog
      when labels[4]  then use_master_flow_catalog
      when labels[5]  then browse_catalog
      when labels[6]  then current_catalog_options
      when labels[7]  then choose_catalog_products
      when labels[8]  then add_tee
      when labels[9]  then add_end_tee
      when labels[10] then add_end_wye
      when labels[11] then add_end_reducer
      when labels[12] then add_end_cover
      when labels[13] then menu_diagnostics
      end

      true
    rescue => error
      puts "UIActions.quick_menu failed: #{error.message}"
      puts error.backtrace.join("\n") if error.backtrace
      false
    end

    def menu_diagnostics
      model = Sketchup.active_model
      tools = model.tools

      ruby_tool =
        begin
          tools.respond_to?(:active_tool) ? tools.active_tool : nil
        rescue
          nil
        end

      get_menu =
        begin
          Tool::DuctTool.instance_method(:getMenu)
        rescue
          nil
        end

      lines = [
        "Simple Duct menu diagnostics",
        "",
        "SketchUp version: #{Sketchup.version}",
        "Native active tool name: #{tools.active_tool_name rescue '(unavailable)'}",
        "Native active tool id: #{tools.active_tool_id rescue '(unavailable)'}",
        "Ruby active tool: #{ruby_tool ? ruby_tool.class.name : '(none / native tool)'}",
        "DuctTool.active_instance: #{active_duct_tool ? 'YES' : 'NO'}",
        "DuctTool#getMenu arity: #{get_menu ? get_menu.arity : '(missing)'}",
        "DuctTool#getMenu source: #{get_menu && get_menu.source_location ? get_menu.source_location.join(':') : '(unknown)'}",
        "Context menu owner: DuctTool#getMenu (application handler disabled)",
        "",
        "The duct tool now uses the same direct getMenu path as the pre-catalog",
        "version. If the native active tool is not Simple Duct, use",
        "'Resume / Activate Duct Tool' and right-click again."
      ]

      ::UI.messagebox(lines.join("\n"), MB_MULTILINE, "Simple Duct Menu Diagnostics")
      true
    rescue => error
      puts "UIActions.menu_diagnostics failed: #{error.message}"
      ::UI.messagebox("Menu diagnostics failed: #{error.message}")
      false
    end

    def draw_duct
      Sketchup.active_model.select_tool(Tool::DuctTool.new)
    end

    def resize_selection
      model = Sketchup.active_model
      Services::SelectionResizeService.run(
        model: model,
        network: DuctExtension.network_for_model(model)
      )
    end

    def add_reducer
      Sketchup.active_model.select_tool(Tool::ReducerTool.new)
    end

    def clear_duct_data
      result = ::UI.messagebox(
        "This will clear all stored duct connection data from this model for performance purposes.\n\n" \
        "The 3D duct geometry will remain unchanged, but old ducts will no longer snap as editable duct pieces.\n\n" \
        "Continue?",
        MB_YESNO
      )
      return false unless result == IDYES

      model = Sketchup.active_model
      Services::NetworkClearService.clear_model_data(
        model,
        DuctExtension.network_for_model(model)
      )
      ::UI.messagebox("Duct data cleared. Geometry was left unchanged.")
      true
    end
  end
end

# ===== Consolidated from: ui/toolbar.rb =====
module DuctExtension
  module Toolbar
    TOOLBAR_NAME = "Simple Duct"

    def self.create
      return if @created

      toolbar = UI::Toolbar.new(TOOLBAR_NAME)

      draw_command = UI::Command.new("Draw Orthogonal Duct") { UIActions.draw_duct }
      draw_command.tooltip = "Draw Orthogonal Duct"
      draw_command.status_bar_text = "Draw round or rectangular duct using orthogonal snap routing."

      resize_command = UI::Command.new("Resize Selected Duct Pieces") { UIActions.resize_selection }
      resize_command.tooltip = "Resize Selected Duct Pieces"
      resize_command.status_bar_text = "Resize selected duct pieces and add boundary reducers/increasers where needed."

      reducer_command = UI::Command.new("Add Increaser / Reducer") { UIActions.add_reducer }
      reducer_command.tooltip = "Add Increaser / Reducer"
      reducer_command.status_bar_text = "Click an open duct end and enter the new size."

      clear_command = UI::Command.new("Clear Duct Data") { UIActions.clear_duct_data }
      clear_command.tooltip = "Clear Duct Data"
      clear_command.status_bar_text = "Clear duct metadata while leaving geometry in place."

      catalog_command = UI::Command.new("Catalog / Mode") { UIActions.set_catalog }
      catalog_command.tooltip = "Catalog / Mode"
      catalog_command.status_bar_text = "Switch between Base / Generic and an installed product catalog."

      browse_command = UI::Command.new("Browse Catalog") { UIActions.browse_catalog }
      browse_command.tooltip = "Browse Catalog"
      browse_command.status_bar_text = "Show the active catalog and available Simple Duct products."

      quick_menu_command = UI::Command.new("Simple Duct Menu") { UIActions.quick_menu }
      quick_menu_command.tooltip = "Simple Duct Menu"
      quick_menu_command.status_bar_text = "Open a compact Simple Duct command menu."

      resume_command = UI::Command.new("Resume Duct Tool") { UIActions.resume_duct_tool }
      resume_command.tooltip = "Resume Duct Tool"
      resume_command.status_bar_text = "Reactivate Simple Duct without changing current settings."

      [
        draw_command,
        quick_menu_command,
        resume_command,
        catalog_command,
        browse_command,
        resize_command,
        reducer_command,
        clear_command
      ].each do |command|
        toolbar.add_item(command)
      end
      toolbar.restore

      @created = true
      toolbar
    rescue => error
      puts "DuctExtension::Toolbar.create failed: #{error.message}"
      nil
    end
  end
end
