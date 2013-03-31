
# Jobs


class window.Job extends Backbone.Model

    initialize: (options) =>
        super options
        options = options || {}
        @refreshModel = options.refreshModel

    idAttribute: "name"

    urlRoot: "/jobs"


class window.JobCollection extends Backbone.Collection

    initialize: (options) =>
        super options
        options = options || {}
        @refreshModel = options.refreshModel
        @filterModel = options.filterModel

    model: Job

    url: "/jobs"

    parse: (resp, options) =>
        resp['jobs']

    comparator: (job) =>
        job.get('name')


class window.JobRun extends Backbone.Model

    initialize: (options) =>
        super options
        options = options || {}
        @refreshModel = options.refreshModel

    idAttribute: "run_num"

    urlRoot: ->
        "/jobs/" + @get('name')

    parse: (resp, options) =>
        resp['job_url'] = "#job/" + resp['job_name']
        resp


class window.JobListFilterModel extends FilterModel

    filterTypes: ['name', 'node_pool', 'status']


class window.JobListView extends Backbone.View

    initialize: (options) =>
        @listenTo(@model, "sync", @render)
        @refreshView = new RefreshToggleView(model: @model.refreshModel)
        @filterView = new FilterView(model: @model.filterModel)
        @listenTo(@refreshView, 'refreshView', => @model.fetch())
        @listenTo(@filterView, "filter:change", @renderList)

    tagName: "div"

    className: "span12"

    template: _.template """
        <h1>
            Jobs
            <span id="refresh"></span>
        </h1>
        <div id="filter-bar"></div>
        <table class="table table-hover">
            <thead>
                <tr>
                    <th>Name</td>
                    <th>Schedule</td>
                    <th>Node Pool</td>
                    <th>Last Success</td>
                    <th>Next Run</td>
                </tr>
            </thead>
            <tbody>
            </tbody>
        </table>
        """

    # TODO: sort by name/state/node
    render: ->
        @$el.html @template()
        @renderFilter()
        @$('#refresh').html(@refreshView.render().el)
        @renderList()
        @

    renderList: =>
        models = @model.filter(@model.filterModel.createFilter())
        entry = (model) -> new JobListEntryView(model: model).render().el
        @$('tbody').html(entry(model) for model in models)


    renderFilter: =>
        @$('#filter-bar').html(@filterView.render().el)


class JobListEntryView extends ClickableListEntry

    initialize: (options) =>
        @listenTo(@model, "change", @render)

    tagName: "tr"

    className: =>
        stateName = switch @model.attributes.status
            when "disabled" then 'warning'
            when "enabled"  then 'enabled'
            when "running"  then 'info'
        "#{ stateName } clickable"

    template: _.template """
        <td><a href="#job/<%= name %>"><%= name %></a></td>
        <td><%= scheduler %></td>
        <td><%= node_pool %></td>
        <td><% print(dateFromNow(last_success, 'never')) %></td>
        <td><% print(dateFromNow(next_run, 'none')) %></td>
        """

    render: ->
        @$el.html @template(@model.attributes)
        makeTooltips(@$el)
        @


class window.JobView extends Backbone.View

    initialize: (options) =>
        @listenTo(@model, "change", @render)
        @refreshView = new RefreshToggleView(model: @model.refreshModel)
        @listenTo(@refreshView, 'refreshView', => @model.fetch())

    tagName: "div"

    className: "span12"

    template: _.template """
        <div class="row">
            <div class="span12">
                <h1>
                    <small>Job</small>
                    <%= name %>
                    <span id="refresh"></span>
                </h1>
            </div>
            <div class="span5">
                <h2>Details</h2>
                <table class="table table-condensed details">
                    <tbody>
                    <tr><td>Status</td>         <td><%= status %></td></tr>
                    <tr><td>Node pool</td>      <td><%= node_pool %></td></tr>
                    <tr><td>Schedule</td>
                        <td><code><%= scheduler %></code></td></tr>
                    <tr><td>Allow overlap</td>
                        <td><%= allow_overlap %></td></tr>
                    <tr><td>Queueing</td>       <td><%= queueing %></td></tr>
                    <tr><td>All nodes</td>      <td><%= all_nodes %></td></tr>
                    <tr><td>Last success</td>
                        <td><% print(dateFromNow(last_success)) %></td></tr>
                    <tr><td>Next run</td>
                        <td><% print(dateFromNow( next_run)) %></td></tr>
                    </tbody>
                </table>
            </div>
            <div class="span7">
                <h2>Action Graph</h2>
                <div id="action_graph" class="graph"></div>
            </div>

            <div class="span12">
                <h2>Job Runs</h2>
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>Id</th>
                            <th>State</th>
                            <th>Node</th>
                            <th>Start</th>
                            <th>End</th>
                        </tr>
                    </thead>
                    <tbody class="jobruns">
                    </tbody>
                </table>
            </div>

        </div>
        """

    render: ->
        @$el.html @template(@model.attributes)
        entry = (jobrun) -> new JobRunListEntryView(model:new JobRun(jobrun)).render().el
        @$('tbody.jobruns').append(entry(model) for model in @model.get('runs'))
        @$('#refresh').html(@refreshView.render().el)
        graph = new GraphView(model: @model.get('action_graph'))
        graph.render()
        makeTooltips(@$el)
        @


class window.GraphView extends Backbone.View

    tagName: "div"

    addLinks: =>
        nodes = {}
        for node in @model
            nodes[node.name] = node

        nested = for node in @model
            ({source: node, target: nodes[target]} for target in node.dependent)

        @links = _.flatten(nested)
        @force.links @links
        @force.start()

        @svg.append("svg:defs")
            .append("svg:marker")
            .attr("id", "arrow")
            .attr("viewBox", "0 0 10 10")
            .attr("refX", 16)
            .attr("refY", 5)
            .attr("markerUnits", "strokeWidth")
            .attr("markerWidth", 7)
            .attr("markerHeight", 7)
            .attr("orient", "auto")
            .append("svg:path")
            .attr("d", "M 0 0 L 10 5 L 0 10 z")

        # TODO: better tooltips
        tooltip = @svg.append('g')
            .attr(fill: "red")
            .classed('d3-tooltip', true)
            .attr(dx: 100, dy: "2em")
            .append('text')
            .attr(fill: "red")

        link = @svg.selectAll(".link")
            .data(@links)
            .enter().append("line")
            .attr("class", "link")
            .attr("marker-end", "url(#arrow)")

        node = @svg.selectAll(".node")
            .data(@model)
            .enter().append("svg:g")
            .attr("class", "node")
            .call(@force.drag)

        node = node.on "mouseover", (d) ->
            mousePos = d3.mouse(d3.select('svg')[0][0])
            tooltip.attr(transform: "translate(#{mousePos})")
            tooltip.text(d.command)
            tooltip.style("display", "block")
        node = node.on "mouseout", (d) ->
            console.log($(tooltip))
            tooltip.style("display", "none")

        node.append("svg:circle")
            .attr("r", "0.5em")

        node.append("svg:text")
            .attr("dx", 12)
            .attr("dy", "0.25em")
            .text((d) -> d.name)

        @force.on "tick", =>
            link.attr("x1", (d) -> d.source.x)
                .attr("y1", (d) -> d.source.y)
                .attr("x2", (d) -> d.target.x)
                .attr("y2", (d) -> d.target.y)

            node.attr("transform", (d) -> "translate(#{d.x}, #{d.y})")

    # TODO: support writing to a modal
    render: =>
        [width, height] = [$('#action_graph').width(), 250]
        # TODO: randomly move nodes when links cross
        @force = d3.layout.force()
            .charge(-500)
            .theta(1)
            .linkDistance(100)
            .size([width, height])

        # TODO: fix how graph is attached
        @svg = d3.select('#action_graph').append("svg")
            .attr("height", height)
        @force.nodes @model
        @addLinks()
        @


class JobRunListEntryView extends ClickableListEntry

    initialize: (options) =>
        @listenTo(@model, "change", @render)

    tagName: "tr"

    className: ->
        stateName = switch @model.get('state')
            when "running"      then 'info'
            when "failed"       then 'error'
            when "succeeded"    then 'success'
        "#{ stateName } clickable"

    # TODO: add icon for manual run flag
    template: _.template """
        <td><a href="#job/<%= job_name %>/<%= run_num %>"><%= id %></a></td>
        <td><%= state %></td>
        <td><%= node %></td>
        <td><% print(dateFromNow(start_time || run_time, "Unknown")) %></td>
        <td><% print(dateFromNow(end_time, "")) %></td>
        """

    render: ->
        @$el.html @template(@model.attributes)
        makeTooltips(@$el)
        @


class window.JobRunView extends Backbone.View

    initialize: (options) =>
        @listenTo(@model, "change", @render)
        @refreshView = new RefreshToggleView(model: @model.refreshModel)
        @listenTo(@refreshView, 'refreshView', => @model.fetch())

    tagName: "div"

    className: "span12"

    template: _.template """
         <div class="row">
            <div class="span12">
                <h1>
                    <small>Job Run</small>
                    <a href="<%= job_url %>"><%= job_name %></a>.<%= run_num %>
                    <span id="filter"</span>
                </h1>

            </div>
            <div class="span5">
                <h2>Details</h2>
                <table class="table table-condensed details">
                    <tr><td class="span2">State</td>
                        <td><%= state %></td></tr>
                    <tr><td>Node</td>           <td><%= node %></td></tr>
                    <tr><td>Manual</td>         <td><%= manual %></td></tr>
                    <tr><td>Scheduled</td>      <td><%= run_time %></td></tr>
                    <tr><td>Start</td>
                        <td><% print(dateFromNow(start_time, 'None')) %></td>
                    </tr>
                    <tr><td>End</td>
                        <td><% print(dateFromNow(end_time, 'None')) %></td>
                    </tr>
                </table>
            </div>

            <div class="span12">
                <h2>Action Runs</h2>
                <table class="table table-hover">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>State</th>
                            <th>Command</th>
                            <th>Exit</th>
                            <th>Node</th>
                            <th>Start</th>
                            <th>End</th>
                        </tr>
                    </thead>
                    <tbody class="actionruns">
                    </tbody>
                </table>
            </div>

        </div>
        """

    render: ->
        @$el.html @template(@model.attributes)
        entry = (run) =>
            run['job_name'] = @model.get('job_name')
            run['run_num'] =  @model.get('run_num')
            new ActionRunListEntryView(model:new ActionRun(run)).render().el
        @$('tbody.actionruns').append(entry(model) for model in @model.get('runs'))
        @$('#filter').html(@refreshView.render().el)
        makeTooltips(@$el)
        @
