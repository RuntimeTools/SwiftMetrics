/*******************************************************************************
 * Copyright 2017 IBM Corp.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not
 * use this file except in compliance with the License. You may obtain a copy of
 * the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 * License for the specific language governing permissions and limitations under
 * the License.
 ******************************************************************************/

// Line chart for displaying average http request response time at a given point in time

var httpDiv2CanvasWidth = $("#httpDiv2").width() - 8; // minus 8 for margin
                                                        // and border
var httpDiv2GraphWidth = httpDiv2CanvasWidth - margin.left - margin.right;

// set the scale dimensions to the size of the graph
var httpTP_xScale = d3.time.scale().range([0, httpDiv2GraphWidth]);
var httpTP_yScale = d3.scale.linear().range([tallerGraphHeight, 0]);

// x axis format
var httpTP_xAxis = d3.svg.axis().scale(httpTP_xScale)
    .orient("bottom")
    .ticks(3)
    .tickFormat(getTimeFormat());

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
var httpThroughPutSVG = d3.select("#httpThroughPutDiv")
    .append("svg")
    .attr("width", httpDiv2CanvasWidth)
    .attr("height", canvasHeight)
    .attr("class", "httpThroughPutChart")

var httpThroughPutTitleBox = httpThroughPutSVG.append("rect")
    .attr("width", canvasWidth)
    .attr("height", 30)
    .attr("class", "titlebox")

var httpThroughPutChart = httpThroughPutSVG.append("g")
    .attr("transform",
        "translate(" + margin.left + "," + margin.top + ")");

// Scale the X range to the time period we have data for
httpTP_xScale.domain(d3.extent(httpRate, function(d) {
    return d.time;
}));

// Scale the Y range from 0 to the maximum http rate
httpTP_yScale.domain([0, d3.max(httpRate, function(d) {
    return d.httpRate;
})]);

// The data line
httpThroughPutChart.append("path")
    .attr("class", "httpline")
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
    .attr("x", 7 - margin.left)
    .attr("y", 15 - margin.top)
    .attr("dominant-baseline", "central")
    .style("font-size", "18px")
    .text("HTTP Throughput");

function updateThroughPutData() {
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
    selection.select(".httpline")
        .attr("d", httpThroughPutline(httpRate));
    selection.select(".xAxis")
        .call(httpTP_xAxis);
    selection.select(".yAxis")
        .call(httpTP_yAxis);

}

function resizeHttpThroughputChart() {
    httpDiv2CanvasWidth = $("#httpThroughPutDiv").width() - 8;
    httpDiv2GraphWidth = httpDiv2CanvasWidth - margin.left - margin.right;

    // only altering the horizontal for the moment
    var chart = d3.select(".httpThroughPutChart")
    chart.attr("width", httpDiv2CanvasWidth);
    httpTP_xScale = d3.time.scale().range([0, httpDiv2GraphWidth]);
    httpTP_xAxis = d3.svg.axis().scale(httpTP_xScale)
        .orient("bottom").ticks(3).tickFormat(getTimeFormat());

    httpThroughPutTitleBox.attr("width", httpDiv2CanvasWidth)

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
    selection.select(".httpline")
        .attr("d", httpThroughPutline(httpRate));
    selection.select(".xAxis")
        .call(httpTP_xAxis);
    selection.select(".yAxis")
        .call(httpTP_yAxis);
}

d3.timer(updateThroughPutData, 2000);
