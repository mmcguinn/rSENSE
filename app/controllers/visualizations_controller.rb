class VisualizationsController < ApplicationController
  include ApplicationHelper
  include ActionView::Helpers::DateHelper
  
  skip_before_filter :authorize, only: [:show, :displayVis, :index, :embedVis]
  
  # GET /visualizations
  # GET /visualizations.json
  def index
        #Main List
    @params = params
    
    if !params[:sort].nil?
      sort = params[:sort]
    else
      sort = "updated_at"
    end
    
    if !params[:order].nil?
      order = params[:order]
    else
      order = "DESC"
    end
    
    if !params[:per_page].nil?
        pagesize = params[:per_page]
    else
        pagesize = 50;
    end
    
    @visualizations = Visualization.search(params[:search]).paginate(page: params[:page], per_page: pagesize)
    
    @visualizations = @visualizations.order("#{sort} #{order}")
    
    respond_to do |format|
      format.html
      format.json { render json: @visualizations.map {|v| v.to_hash(false) } }
    end
    
  end

  # GET /visualizations/1
  # GET /visualizations/1.json
  def show
    @visualization = Visualization.find(params[:id])
    @project = Project.find_by_id(@visualization.project_id)

    # The finalized data object
    @Data = { savedData: @visualization.data, savedGlobals: @visualization.globals }

    recur = params.key?(:recur) ? params[:recur] == "true" : false
    
    options = {}
    
    # Detect presentation mode (and force embed)
    if params.try(:[], :presentation) and params[:presentation]
      @presentation = true
      options[:presentation] = 1
      params[:embed] = true
    else
      @presentation = false
    end
    
    respond_to do |format|
      format.html do
        if params.try(:[], :embed) and params[:embed]
          options[:isEmbed] = 1
          options[:startCollapsed] = 1
          @Globals = { options: options }
          render 'embed', :layout => 'embedded'
        else
          @layout_wide = true
          render
        end
      end
      format.json { render json: @visualization.to_hash(recur) }
    end
  end

  def edit
    @visualization = Visualization.find(params[:id])
  end

  # POST /visualizations
  # POST /visualizations.json
  def create
    params[:visualization][:user_id] = @cur_user.id
    
    # Remove any piggybacking updates
    if params[:visualization].try(:[], :tn_file_key)
      params[:visualization].delete :tn_file_key
    end
    if params[:visualization].try(:[], :tn_src)
      params[:visualization].delete :tn_src
    end
    
    #Try to make a thumbnail
    mo = MediaObject.new
    mo.media_type = 'image'
    mo.name = 'image.png'
    mo.check_store!
   
    if params[:visualization].try(:[], :svg)
      begin
        image = MiniMagick::Image.read(params[:visualization][:svg], '.svg')
        image.format 'png'
        image.resize '512'
        
        File.open(mo.file_name, "wb") do |ff|
          ff.write(image.to_blob)
        end
      
        mo.add_tn
      
      rescue MiniMagick::Invalid => err
        logger.info "Failed to create thumbnail."
      end

      params[:visualization].delete :svg
    end
    
    @visualization = Visualization.new(visualization_params)
    @visualization.thumb_id = mo.id unless mo.id.nil?

    respond_to do |format|
      if @visualization.save
        mo.visualization_id = @visualization.id
        mo.save!

        flash[:notice] = 'Visualization was successfully created.'
        format.html { redirect_to @visualization }
        format.json { render json: @visualization.to_hash(false), status: :created}
      else
        format.html { render action: "new" }
        format.json { render json: @visualization.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /visualizations/1
  # PUT /visualizations/1.json
  def update
    @visualization = Visualization.find(params[:id])
    update = visualization_params
   
    #ADMIN REQUEST
    if can_admin?(@visualization) 
      if update.has_key?(:featured)
        if update['featured'] == "1"
          update['featured_at'] = Time.now()
        else
          update['featured_at'] = nil
        end
      end
    end
    
    respond_to do |format|
      if can_edit?(@visualization) && @visualization.update_attributes(update)
        format.html { redirect_to @visualization, notice: 'Visualization was successfully updated.' }
        format.json { render json: {}, status: :ok }
      else
        @visualization.errors[:base] << "Permission denied" unless can_edit(@visualization)
        format.html { render action: "edit" }
        format.json { render json: @visualization.errors.full_messages(), status: :unprocessable_entity }
      end
    end
  end

  # DELETE /visualizations/1
  # DELETE /visualizations/1.json
  def destroy
    @visualization = Visualization.find(params[:id])
    
    if can_delete?(@visualization)
      
      @visualization.media_objects.each do |m|
        m.destroy
      end
      
      @visualization.hidden = true
      @visualization.user_id = -1
      @visualization.save
      
      respond_to do |format|
        format.html { redirect_to visualizations_url }
        format.json { render json: {}, status: :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to 'public/401.html' }
        format.json { render json: {}, status: :forbidden }
      end
    end
  end

  # GET 
  def displayVis
    
    @project = Project.find_by_id params[:id]
    
    @datasets = []
    data_fields = []
    format_data = []
    metadata = {}
    rel_viz = []
    total = 0
    field_count = []
    
    # build list of datasets
    if( !params[:datasets].nil? )
      
      dsets = params[:datasets].split(",")
      dsets.each do |id|
        begin
          dset = DataSet.find_by_id(id.to_i)
          if dset.project_id == @project.id
            @datasets.push dset
          end
        rescue
          logger.info "Either project id or dataset does not exist in the DB"
        end
      end
    else
      @datasets = DataSet.where(hidden: false, project_id: params[:id])
    end
    
    # create special dataset grouping field
    data_fields.push({ typeID: TEXT_TYPE, unitName: "String", fieldID: -1, fieldName: "Dataset Name (id)" })
    # create special grouping field for all datasets
    data_fields.push({ typeID: TEXT_TYPE, unitName: "String", fieldID: -1, fieldName: "Combined Datasets" })
    
    # push real fields to temp variable
    @project.fields.each do |field|
      data_fields.push({ typeID: field.field_type, unitName: field.unit, fieldID: field.id, fieldName: field.name })
    end
    
    hasPics = false
    # create/push metadata for datasets
    i = 0
    @datasets.each do |dataset|
      photos = dataset.media_objects.keep_if{|mo| mo.media_type=="image"}.map{|mo| mo.to_hash(true)}
      hasPics = true if photos.size > 0
      metadata[i] = { name: dataset.title, user_id: dataset.user_id, dataset_id: dataset.id, timecreated: dataset.created_at, timemodified: dataset.updated_at, photos: photos}
      dataset.data.each do |row|
        unless row.class == Hash
          logger.info "Bad row in JSON data:"
          logger.info row.inspect
        end

        arr = []
        arr.push "#{dataset.title}(#{dataset.id})"
        arr.push "All"

        data_fields.slice(2, data_fields.length).each do |field|
          arr.push row[field[:fieldID].to_s]
        end
        format_data.push arr
      end
      i+=1
    end
    
    #Count the number of each type of field
    field_count = [0,0,0,0,0,0]
    @project.fields.each do |field|
      field_count[field.field_type] += 1 
    end
    
    rel_vis = []

    # Determine which visualizations are relevant
    if field_count[LONGITUDE_TYPE] > 0 and field_count[LATITUDE_TYPE] > 0
      rel_vis.push "Map"
    end

    if field_count[TIME_TYPE] > 0 and field_count[NUMBER_TYPE] > 0 and format_data.count > 1
      rel_vis.push "Timeline"
    end
    
    if field_count[NUMBER_TYPE] > 1 and format_data.count > 1
      rel_vis.push "Scatter"
    end
    
    if field_count[NUMBER_TYPE] > 0 and format_data.count > 1
      rel_vis.push "Bar"
      rel_vis.push "Histogram"
    end
    
    rel_vis.push "Table"
    
#     if field_count[TIME_TYPE] > 0 and field_count[NUMBER_TYPE] > 0 and format_data.count > 1
#       rel_vis.push "Motion"
#     end
    
    if hasPics
      rel_vis.push "Photos"
    end
    
    # A list of all current visualizations
    allVis =  ['Map','Timeline','Scatter','Bar','Histogram','Table','Photos']

    # Defaut vis if one exists for the project
    defaultVis = @project.default_vis.nil? ? "none" : @project.default_vis

    # The finalized data object
    @Data = { projectName: @project.title, projectID: @project.id, fields: data_fields, dataPoints: format_data, metadata: metadata, relVis: rel_vis, allVis: allVis, defaultVis: defaultVis }

    options = {}
    
    # Detect presentation mode (and force embed)
    if params.try(:[], :presentation) and params[:presentation]
      @presentation = true
      options[:presentation] = 1
      params[:embed] = true
    else
      @presentation = false
    end
    
    respond_to do |format|
      format.html do
        if params.try(:[], :embed) and params[:embed]
          options[:isEmbed] = 1
          options[:startCollapsed] = 1
          @Globals = { options: options }
          render 'embed', :layout => 'embedded'
        else
          @layout_wide = true
          render
        end
      end
    end
  end
 
  private

  def visualization_params
    if @cur_user.try(:admin)
      params[:visualization].permit(:content, :data, :project_id, :globals, :title, :user_id, :featured, 
                                    :featured_at, :tn_src, :tn_file_key, :summary, :thumb_id)
    else
      params[:visualization].permit(:content, :data, :project_id, :globals, :title, :user_id,
                                    :tn_src, :tn_file_key, :summary, :thumb_id)
    end
  end
end
