# Copyright (c) 2012 Daniel Richman; GNU GPL 3

# Current editing state
flight_callback = null
flight_no_show_dates = false

# Main start point for flight editing. #flight should be visible.
# Loads data from doc into the forms and enables editing. callback(doc) is called when the doc
# has been successfully saved to the database or callback(false) is called if the user cancels.
flight_edit = (doc, callback, pcfgs={}) ->
    flight_callback = callback

    if not doc?
        # Empty fields.
        default_time_settings = true
        doc =
            name: ""
            launch:
                location:
                    latitude: ""
                    longitude: ""
                    altitude: ""
            metadata:
                location: ""
                project: ""
                group: ""
            payloads: []
    else
        default_time_settings = false

    $("#flight_name").val doc.name
    $("#flight_project").val doc.metadata.project
    $("#flight_group").val doc.metadata.group
    $("#launch_location_name").val doc.metadata.location or ""
    $("#flight_name, #flight_project, #flight_group, #launch_location_name").change()

    $("#launch_latitude").val doc.launch.location.latitude
    $("#launch_longitude").val doc.launch.location.longitude
    $("#launch_latitude, #launch_longitude").change()

    try
        flight_no_show_dates = true

        if default_time_settings
            $("#launch_timezone").val "Europe/London"
            $("#launch_window").val "day"
            $("#launch_time").val ""
            $("#launch_date").datepicker "setDate", new Date() # set to today

            $("#launch_time, #launch_window, #launch_timezone").change()
            # updates (hidden) launch_window_start/end, adds/removes weekend option, calls flight_show_dates
            flight_launch_date_change()
            # firing events of launch_window_start/end unnecessary since they just call flight_show_dates

        else
            $("#launch_timezone").val doc.launch.timezone
            launch = new timezoneJS.Date(doc.launch.time, doc.launch.timezone)
            $("#launch_date").datepicker "setDate", new Date(launch.year, launch.month, launch.date)
            if launch.seconds != 0
                $("#launch_time").val launch.toString("HH:mm:ss")
            else
                $("#launch_time").val launch.toString("HH:mm")

            flight_launch_date_change()
            $("#launch_time, #launch_timezone").change()

            # only used if we get to 'other'
            sd = new timezoneJS.Date(doc.start, doc.launch.timezone)
            ed = new timezoneJS.Date(doc.end, doc.launch.timezone)
            $("#launch_window_start").datepicker "setDate", new Date(sd.year, sd.month, sd.date)
            $("#launch_window_end").datepicker "setDate", new Date(ed.year, ed.month, ed.date)

            # this is a bit ugly, but simple. If there were more options, perhaps it should be reconsidered
            for attempt in $("#launch_window").children("option")
                # select it, then see if it produces the same result:
                $("#launch_window").val $(attempt).val()
                dates = flight_get_dates()
                if dates.data.launch_time.getTime() != launch.getTime()
                    throw "timezone fail"

                if (dates.data.start.getTime() == sd.getTime()) and (dates.data.end.getTime() == ed.getTime())
                    break

            $("#launch_window").change()

            # If nothing works, it will be set at other, with an approximately the right datetimes.

    finally
        flight_no_show_dates = false

    $("#flight_pcfgs_list").empty()
    flight_add_payload pcfgs[p] for p in doc.payloads

    flight_show_dates()

# Save doc, call callback
flight_save = ->
    try
        dates = flight_get_dates()
    catch e
        alert "There are errors in your form: #{e}"
        return

    doc =
        type: "flight"
        approved: false
        name: $("#flight_name").val()
        start: dates.data.start.toRFC3339String()
        end: dates.data.end.toRFC3339String()
        launch:
            time: dates.data.launch_time.toRFC3339String()
            timezone: dates.data.timezone
            location:
                latitude: strict_numeric $("#launch_latitude").val()
                longitude: strict_numeric $("#launch_longitude").val()
        metadata:
            location: $("#launch_location_name").val()
            project: $("#flight_project").val()
            group: $("#flight_group").val()
        payloads: (array_data_map "#flight_pcfgs_list", "pcfg_id")

    valid = true

    alt = $("#launch_altitude").val()
    if alt != ""
        doc.launch.location.altitude = strict_numeric alt
        if isNaN doc.launch.location.altitude
            valid = false
    if (isNaN doc.launch.location.latitude) or (isNaN doc.launch.location.longitude)
        valid = false
    if not (-90 <= doc.launch.location.latitude <= 90)
        valid = false
    if not (-180 < doc.launch.location.longitude <= 180)
        valid = false

    if doc.metadata.location == ""
        delete doc.metadata.location
    if doc.metadata.project == ""
        delete doc.metadata.project
    if doc.metadata.group == ""
        delete doc.metadata.group
    # leave metadata = {}

    if doc.name == ""
        valid = false

    if not valid
        alert "There are errors in your form. Please fix them"
        return

    if doc.payloads.length == 0
        alert "You should probably add atleast one payload to your flight document"
        return

    toplevel "#saving"
    save_doc doc, (saved) ->
        toplevel "#flight"
        if saved?
            flight_callback saved

# Return object with keys launch, start, end describing the 3 dates in the flight.
flight_get_dates = ->
    timezone = $("#launch_timezone").val()

    ld = $("#launch_date").datepicker "getDate"
    if ld == null
        throw "No launch date selected"
    time = time_parse $("#launch_time").val()
    launch = new timezoneJS.Date(ld.getFullYear(), ld.getMonth(), ld.getDate(), time[0], time[1], time[2], 0, timezone)

    switch $("#launch_window").val()
        when "day"
            start = new timezoneJS.Date(launch.year, launch.month, launch.date, 0, 0, 0, 0, timezone)
            end = new timezoneJS.Date(launch.year, launch.month, launch.date, 23, 59, 59, 0, timezone)

        when "three"
            start = new timezoneJS.Date(launch.year, launch.month, launch.date - 1, 0, 0, 0, 0, timezone)
            end = new timezoneJS.Date(launch.year, launch.month, launch.date + 1, 23, 59, 59, 0, timezone)

        when "weekend"
            diff = if launch.getDay() == 0 then [-1, 0] else [0, 1]
            start = new timezoneJS.Date(launch.year, launch.month, launch.date + diff[0], 0, 0, 0, 0, timezone)
            end = new timezoneJS.Date(launch.year, launch.month, launch.date + diff[1], 23, 59, 59, 0, timezone)

        when "other"
            sd = $("#launch_window_start").datepicker "getDate"
            ed = $("#launch_window_end").datepicker "getDate"
            if sd == null or ed == null
                throw "Start or end dates not selected"
            start = new timezoneJS.Date(sd.getFullYear(), sd.getMonth(), sd.getDate(), 0, 0, 0, 0, timezone)
            end = new timezoneJS.Date(ed.getFullYear(), ed.getMonth(), ed.getDate(), 23, 59, 59, 0, timezone)

    display = (d, utc=false) ->
        if utc
            d.toString null, "Etc/UTC"
        else
            d.toString()

    return {
        data:
            launch_time: launch
            start: start
            end: end
            timezone: timezone
        display:
            launch_time: display launch
            start: display start
            end: display end
        display_utc:
            launch_time: (display launch, true)
            start: (display start, true)
            end: (display end, true)
    }

flight_show_dates = ->
    if flight_no_show_dates
        return

    try
        data = flight_get_dates()
    catch e
        data = null

    if data?
        $("#launch_time_check").text "Launch time: #{data.display.launch_time}"
        $("#launch_time_check").attr "title", "UTC: #{data.display_utc.launch_time}"
        $("#launch_window_info").text "Launch window: #{data.display.start} - #{data.display.end}"
        $("#launch_window_info").attr "title", "UTC: #{data.display_utc.start} - #{data.display_utc.end}"
    else
        $("#launch_time_check, #launch_window_info").text("").attr("title", "")

# onSelect of #launch_date doesn't appear to use jQuery events. flight_edit needs to call it, so...
flight_launch_date_change = ->
    date = $("#launch_date").datepicker "getDate"

    lw = $("#launch_window")
    wko = lw.children('[value="weekend"]')

    if date.getDay() in [0, 6]
        # weekend
        if wko.length == 0
            lw.children().last().before $("<option>weekend</option>")
    else
        if wko.length == 1
            if lw.val() == "weekend"
                lw.val "three"
                lw.change()

            wko.remove()

    $("#launch_window_start").datepicker "option", "maxDate", date
    $("#launch_window_end").datepicker "option", "minDate", date

    if $("#launch_window").val() != "other"
        # So that if they open the other dialogue, it's not in some random place
        $("#launch_window_start, #launch_window_end").datepicker "setDate", date

    flight_show_dates()

flight_add_payload = (pcfg) ->
    row = $("<tr />")

    row.append $("<td />").text pcfg.name
    info = $("<td class='small' />")
    info.append $("<div />").text pcfg._id
    localestring = (new timezoneJS.Date pcfg.time_created).toString()
    info.append $("<div />").text("created " + pcfg.time_created).attr("title", localestring)
    row.append info
    row.append $("<td />").append $("<a href='#'>Delete</a>").button().click -> row.remove()
    row.data "pcfg_id", pcfg._id

    $("#flight_pcfgs_list").append row

setup_flight_form = ->
    form_field "#flight_name"
        nonempty: true

    form_field "#launch_timezone"
        nonempty: true
        extra: (s) -> s? and s != "null" and timezone_js_data.zones[s]?

    $("#launch_timezone").autocomplete
        source: timezone_list

    $("#launch_date").datepicker
        onSelect: (text, inst) -> flight_launch_date_change()

    $("#launch_window_start, #launch_window_end").datepicker
        onSelect: (text, inst) -> flight_show_dates()

    form_field "#launch_time"
        extra: (s) -> time_regex.test s

    $("#launch_time").change flight_show_dates
    $("#launch_timezone").change flight_show_dates

    $("#launch_window").change ->
        if $("#launch_window").val() == "other"
            $("#launch_window_start, #launch_window_end").show()
        else
            $("#launch_window_start, #launch_window_end").hide()
        flight_show_dates()

    $("#launch_location_name").autocomplete
        source: suggest_launch_data
        select: (e, ui) ->
            if ui.item
                $("#launch_latitude").val(ui.item.latitude).change()
                $("#launch_longitude").val(ui.item.longitude).change()
        minLength: 0

    # Encourage the autocomplete box to open more often
    $("#launch_location_name").click -> $(this).autocomplete "search"

    form_field "#launch_latitude"
        nonempty: true
        numeric: true
        extra: (v) -> -90 <= (strict_numeric v) <= 90
    form_field "#launch_longitude"
        nonempty: true
        numeric: true
        extra: (v) -> -180 < (strict_numeric v) <= 180

    $("#flight_pcfgs_add").click ->
        toplevel "#browse"
        browse "payload_configuration", (p) ->
            toplevel "#flight"
            if p
                flight_add_payload p

$ ->
    setup_flight_form()
    $("#flight_save").click flight_save
    $("#flight_abandon").click -> flight_callback false
