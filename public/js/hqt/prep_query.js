/*
##############################################################################
#                                                                            #
#   Copyright 2013 TripAdvisor, LLC                                          #
#                                                                            #
#   Licensed under the Apache License, Version 2.0 (the "License");          #
#   you may not use this file except in compliance with the License.         #
#   You may obtain a copy of the License at                                  #
#                                                                            #
#       http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                            #
#   Unless required by applicable law or agreed to in writing, software      #
#   distributed under the License is distributed on an "AS IS" BASIS,        #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. #
#   See the License for the specific language governing permissions and      #
#   limitations under the License.                                           #
#                                                                            #
##############################################################################
*/
var hqt = {};
hqt.prep_query = {

  // toggles the query text and flips the button label too
  toggleQueryText: function () {
    $('.query_text').toggle();
    if( $('.query_text').is(':visible') ) {
       $('#QUERY_BTN').val("Hide Query");
    }
    else {
      $('#QUERY_BTN').val("Show Query");
    }
  },

  // append a where clause to the element passed in
  addWhereClause: function(clause_elements_parent) {
    var new_where = $('#WHERE_CLAUSE_HIDDEN').clone().removeAttr('id');
    if(( $(clause_elements_parent).children('.where_clause') && ( $(clause_elements_parent).children('.where_clause').length > 0) ) ) {
      var new_logical_op = $('#WHERE_LOGICAL_OP').clone().removeAttr('id').removeClass('hidden');
      $(clause_elements_parent).append(new_logical_op);
    }
    $(clause_elements_parent).append(new_where);
  },

  // append an inner where clause to the element passed in
  addInnerWhereClause: function(clause_elements_parent) {
    var new_inner_where = $('#WHERE_CLAUSE_CONTAINER').clone().removeClass('hidden').removeAttr('id');
    if(( $(clause_elements_parent).children('.where_clause') && ( $(clause_elements_parent).children('.where_clause').length > 0) ) ) {
      var new_logical_op = $('#WHERE_LOGICAL_OP').clone().removeAttr('id').removeClass('hidden');
      $(clause_elements_parent).append(new_logical_op);
    }
     $(clause_elements_parent).append(new_inner_where);
  },

  // remove the given where clause element and corresponsding logic operator before it too.
  removeWhereClause: function(whereClauseElement) {
    if($(whereClauseElement).next().is('.where_logic_op')) {
      $(whereClauseElement).next().remove();
    }
    else if( $(whereClauseElement).is(":last-child") && $(whereClauseElement).prev().is('.where_logic_op')) {
       $(whereClauseElement).prev().remove();
    }
    $(whereClauseElement).remove();
  },

  // used to get json for the inner where clause. see process_where_clause function for more details
  process_inner_where: function( clause_element) {
    if(!($(clause_element).is('.inner_where_clause'))) return;
    // if inner where clause is empty
    if($(clause_element).children('.where_clause').length == 0) {
      throw "Empty Inner Where clause. If you don't want it please remove this clause.";
    }
    else {
      return hqt.prep_query.process_where_clause($(clause_element).children('.where_clause').first(), true);
    }
  },

  // filling in values for a single where clause
  construct_unary_clause: function( clause_element, is_inner_clause) {
    var clause_obj = {};
    if(is_inner_clause) {
      clause_obj["inner"] = "true";
    }
    clause_obj["type"] = "unary";
    clause_obj["col_name"] = $(clause_element).children('.col_name').val();
    clause_obj["col_relational_op"] = $(clause_element).children('.col_relational_op').val();
    clause_obj["col_value"] = $(clause_element).children('.col_value').val();
    return clause_obj;
  },

   /* construct the json object representing the where clause
     here is an example
       clause 1 = val1 AND ( clause2 = val2 or clause3 = val3)
     will be represented as the below json
     { type: 'binary',
           clause1: {
             type: 'unary',
             col_name: col1,
             col_relational_op: =,
             col_value: val1
           },
           logical_op : AND,
           clause2: {
             type: 'binary',
             inner: true,
             clause1: {
             type : unary,
             col_name: col2,
             col_relational_op : !=,
             col_value: val2
          },
         clause2: {
           type: unary,
           col_name: col3,
           col_relational_op : <,
           col_value: val3
         }
     }
  */
  process_where_clause: function(clause_element, is_inner) {
    // if this last where clause
    if($(clause_element).nextAll('.where_clause').length == 0) {
      // if the element is a inner clause
      if($(clause_element).is('.inner_where_clause')) {
        return hqt.prep_query.process_inner_where(clause_element, true);
      }
      // if it is last clause
      else {
        return hqt.prep_query.construct_unary_clause(clause_element, is_inner);
      }
    }
    // if it is not the last clause
    else {
      var where_clauses_obj = {};
      where_clauses_obj["type"] = "binary";
      if(is_inner){
        where_clauses_obj["inner"] = "true";
      }
      // process clause1 - if it is an inner clause, then process that, else unary clause
      if($(clause_element).is('.inner_where_clause')) {
        where_clauses_obj["clause1"] = hqt.prep_query.process_inner_where(clause_element);
      }
      else {
        where_clauses_obj["clause1"] = hqt.prep_query.construct_unary_clause(clause_element, false);
      }

      // store the logical operator
      var logical_operator_element = $(clause_element).next('div.where_logic_op');
      where_clauses_obj["logical_op"]=$(logical_operator_element).children('.logical_op').val();

      // process clause2
      where_clauses_obj["clause2"]  = hqt.prep_query.process_where_clause($(logical_operator_element).next('div.where_clause'));

      return where_clauses_obj;
    }
  },

  // adding a new group by clause to the page
  addGrooupByClause: function(clause_elements_parent) {
    var new_group_by = $('#GROUP_CLAUSE_HIDDEN').clone().removeAttr('id');
    $(clause_elements_parent).append(new_group_by);
  },

  // construct an array of group by clause to be passed to the server
  process_group_by: function() {
    var group_by_arr = new Array();
    $('#GROUP_BY_CLAUSES').children('div.group_by_clause').each( function() {
      group_by_arr .push( $(this).children('.group_by_col') .val());
    });
    return group_by_arr;
  },

  // prepare all user inputs - variables, where clause, group by to be sent to the server as a JSON
  prepareUserInputs: function() {
    var input_vars = {};
    if($('.query_variables')) {
      var query_vars = {};
      $('.query_variables').each( function() {
        query_vars[this.name] = $(this).val();
      });
      input_vars['var'] = query_vars;
    }
    if($('#WHERE_CLAUSES').children('div.where_clause').length > 0) {
      try {
        input_vars['where'] = hqt.prep_query.process_where_clause($('#WHERE_CLAUSES').children('div.where_clause').first());
      }
      catch(err) {
        alert("Failed due to error: " + err);
        return false;
      }
    }
    if($('#GROUP_BY_CLAUSES').children('div.group_by_clause').length > 0) {
      input_vars['group'] = hqt.prep_query.process_group_by();
    }
    $('.input_vars').val(JSON.stringify(input_vars));
    return true;
  },

  // prepare inputs and preview Query
  previewQuery: function() {
    if(hqt.prep_query.validateQueryInputs() && hqt.prep_query.prepareUserInputs()) {
      var form_data = $('form').serialize();
      $.ajax( {
        type: "POST",
        async: false,
        url: '/preview-query',
        data: form_data,
        success: function(data) {
          if(data.query) {
            hqt.prep_query.showOutput( data.query, false);
          }
          else {
            hqt.prep_query.showOutput( data.error_msg, true);
          }
        }
      });
    }
  },

  // display the given textMsg in the prepared_query div. Colors red or not based on isError
  showOutput: function( textMsg, isError) {
    if( isError) {
      $('.prepared_query').addClass('red');
    }
    else {
      $('.prepared_query').removeClass('red');
      textMsg = 'Preview the query below:(the $output_directory_path  will be filled in when the query runs)\n\n' + textMsg;
    }
    $('.prepared_query').text(textMsg);
    $('.prepared_query').show();
  },

  // prepares input variables and run the query. Redirects the page to obtained url in case of success. Else shows up the errors in the prepared_query div
  processQuery: function() {
    if(hqt.prep_query.validateQueryInputs() && hqt.prep_query.prepareUserInputs()) {
      var form_data = $('form').serialize();
      $.ajax( {
        type: "POST",
        async: false,
        url: '/run-query',
        data: form_data,
        success: function(data) {
          if(data.error_msg){
            hqt.prep_query.showOutput( data.error_msg, true);
          }
          else if(data.redirect_url) {
            window.location.href = data.redirect_url;
          }
        }
      });
    }
  },

  // validate the inputs
  validateQueryInputs: function() {
    // checking if any query variables are empty
    if($('.query_variables')) {
        var isValid = true;
        $('.query_variables').each( function() {
        if($.trim($(this).val()).length == 0) {
          $(this).next('.error_msg').show();
          isValid = false;
        }
        else {
          $(this).next().hide();
        }
      }
      );
      return isValid;
    }
    return true;
  },

  // validate inputs and prepare to run the query
  runQuery: function() {
    var isValid = true;
    if($.trim($('.email_box').val()).length == 0) {
      $('.email_box').next('.error_msg').show();
      isValid = false;
    }
    else {
      $('.email_box').next('.error_msg').hide();
    }

    if( isValid ) {
      hqt.prep_query.processQuery();
    }
  }


};
$(document).ready( function() {
  $('.date').datepicker({ dateFormat: "yy-mm-dd", maxDate: -2 });

});
