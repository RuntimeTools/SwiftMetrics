//set the scale dimensions to the size of the graph
var httpTP_xScale = d3.time.scale().range([0, graphWidth]);
var httpTP_yScale = d3.scale.linear().range([tallerGraphHeight, 0]);

// graph data storage
var httpRate = [];

// x axis format
var httpTP_xAxis = d3.svg.axis().scale(httpTP_xScale)
    .orient("bottom").ticks(3).tickFormat(d3.time.format("%H:%M:%S"));

// y axis format, in requests per second
var httpTP_yAxis = d3.svg.axis().scale(httpTP_yScale)
    .orient("left").ticks(5).tickFormat(function(d) {
        return d + " rps";
    });

// line plot function
var httpThroughPutline = d3.svg.line()
    .x(function(d) {
        return httpTP_xScale(d.time);
    })
    .y(function(d) {
        return httpTP_yScale(d.httpRate);
    });

// create the chart canvas
var httpThroughPutChart = d3.select("#httpDiv2")
    .append("svg")
    .attr("width", canvasWidth)
    .attr("height", canvasHeight)
    .attr("class", "httpThroughPutChart")
    .append("g")
    .attr("transform",
        "translate(" + margin.left + "," + margin.shortTop + ")");

// Scale the X range to the time period we have data for
httpTP_xScale.domain(d3.extent(httpRate, function(d) {
    return d.time;
}));

//Scale the Y range from 0 to the maximum http rate
httpTP_yScale.domain([0, d3.max(httpRate, function(d) {
    return d.httpRate;
})]);

//The data line
httpThroughPutChart.append("path")
    .attr("class", "line")
    .attr("d", httpThroughPutline(httpRate));

// X axis line
httpThroughPutChart.append("g")
    .attr("class", "xAxis")
    .attr("transform", "translate(0," + tallerGraphHeight + ")")
    .call(httpTP_xAxis);

// Y axis line
httpThroughPutChart.append("g")
    .attr("class", "yAxis")
    .call(httpTP_yAxis);

// Chart title
httpThroughPutChart.append("text")
    .attr("x", -20)
    .attr("y", 0 - (margin.shortTop * 0.5))    
    .attr("text-anchor", "left")
    .style("font-size", "18px")
    .text("HTTP Throughput");

function updateThroughPutData() {

    request = "http://" + myurl + "/httpRate";
    d3.json(request, function(error, data) {
        if (error) return console.warn(error);
        if (data == null) return;

        // store incoming data
        httpRate.push(data)

        // Only keep 30 minutes of data
        var currentTime = Date.now()
        var d = httpRate[0]
        while (d.hasOwnProperty('time') && d.time.valueOf() + 1800000 < currentTime) {
            httpRate.shift()
            d = httpRate[0]
        }

        // Re-scale the x range to the new time interval
        httpTP_xScale.domain(d3.extent(httpRate, function(d) {
            return d.time;
        }));

        // Re-scale the y range to the new maximum http rate
        httpTP_yScale.domain([0, d3.max(httpRate, function(d) {
            return d.httpRate;
        })]);

        // update the data and axes lines to the new data values
        var selection = d3.select(".httpThroughPutChart");
        selection.select(".line")
            .attr("d", httpThroughPutline(httpRate));
        selection.select(".xAxis")
            .call(httpTP_xAxis);
        selection.select(".yAxis")
            .call(httpTP_yAxis);
    });
}

function resizeHttpThroughputChart() {
    //only altering the horizontal for the moment
    var chart = d3.select(".httpThroughPutChart")
    chart.attr("width", canvasWidth);
    httpTP_xScale = d3.time.scale().range([0, graphWidth]);
    httpTP_xAxis = d3.svg.axis().scale(httpTP_xScale)
        .orient("bottom").ticks(3).tickFormat(d3.time.format("%H:%M:%S"));

    // Re-scale the x range to the new time interval
    httpTP_xScale.domain(d3.extent(httpRate, function(d) {
        return d.time;
    }));

    // Re-scale the y range to the new maximum http rate
    httpTP_yScale.domain([0, d3.max(httpRate, function(d) {
        return d.httpRate;
    })]);

    // update the data and axes lines to the new data values
    var selection = d3.select(".httpThroughPutChart");
    selection.select(".line")
        .attr("d", httpThroughPutline(httpRate));
    selection.select(".xAxis")
        .call(httpTP_xAxis);
    selection.select(".yAxis")
        .call(httpTP_yAxis);
}

setInterval(updateThroughPutData, 2000);
