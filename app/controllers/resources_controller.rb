class ResourcesController < ApplicationController
  def index
    params[:per_page] ||= 50
    @resources = prep_for_api(Resource.order(:name).includes([:partner]))
  end

  def show
    @resource = Resource.find(params[:id])
    @formats = Format.where(resource_id: @resource.id).abstract
    respond_to do |fmt|
      fmt.html do
        @root_nodes = @resource.nodes.published.root.order("canonical, resource_pk").page(params[:page] || 1)
                               .per(params[:per] || 10)
      end
      # TODO: add the "since" param...
      fmt.json { }
    end
  end

  def harvest
    @resource = Resource.find(params[:resource_id])
    count = Delayed::Job.where(locked_at: nil).count
    @resource.delay.harvest
    flash[:notice] = t("resources.actions.harvest_enqueued", count: count)
    redirect_to @resource
  end

  def new
    @resource = Resource.new
  end

  def edit
    @resource = Resource.find(params[:id])
  end

  def create
    @resource = Resource.new(resource_params)
    if @resource.save
      flash[:notice] = I18n.t("resources.flash.created", name: @resource.name,
        path: resource_path(@resource)).html_safe
      redirect_to @resource
    else
      # TODO: some kind of hint as to the problem, in a flash...
      render "new"
    end
  end

  def update
    @resource = Resource.find(params[:id])

    if @resource.update(resource_params)
      flash[:notice] = I18n.t("resources.flash.updated", name: @resource.name,
        path: resource_path(@resource))
      redirect_to @resource
    else
      # TODO: some kind of hint as to the problem, in a flash...
      render "edit"
    end
  end

  def destroy
    @resource = Resource.find(params[:id])
    name = @resource.name
    @resource.destroy
    flash[:notice] = I18n.t("resources.flash.destroyed", name: name)
    redirect_to resources_path
  end

private

  def resource_params
    params.require(:resource).permit(:name, :abbr, :pk_url,
      :min_days_between_harvests, :harvest_day_of_month, :harvest_months_json,
      :auto_publish, :not_trusted, :might_have_duplicate_taxa)
  end
end
