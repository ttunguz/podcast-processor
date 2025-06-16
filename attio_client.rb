require 'httparty'
require 'json'

class AttioClient
  include HTTParty
  base_uri 'https://api.attio.com/v2'
  
  def initialize(api_key)
    @api_key = api_key
    @headers = {
      'Authorization' => "Bearer #{api_key}",
      'Content-Type' => 'application/json'
    }
  end

  def search_companies(company_names)
    results = {}
    
    company_names.each do |company|
      response = self.class.post(
        '/objects/companies/records/query',
        headers: @headers,
        body: {
          filter: {
            operator: 'or',
            conditions: [
              {
                attribute_id: 'name',
                operator: 'contains',
                value: company
              }
            ]
          },
          limit: 5
        }.to_json
      )
      
      if response.success?
        results[company] = response.parsed_response['records']
      else
        puts "Error searching for company #{company}: #{response.code} - #{response.body}"
        results[company] = []
      end
    end
    
    results
  end

  def search_people(people_names)
    results = {}
    
    people_names.each do |name|
      # Split name into parts for more comprehensive search
      name_parts = name.split(/\s+/)
      
      conditions = name_parts.map do |part|
        [
          {
            attribute_id: 'first_name',
            operator: 'contains',
            value: part
          },
          {
            attribute_id: 'last_name',
            operator: 'contains',
            value: part
          }
        ]
      end.flatten
      
      response = self.class.post(
        '/objects/people/records/query',
        headers: @headers,
        body: {
          filter: {
            operator: 'or',
            conditions: conditions
          },
          limit: 5
        }.to_json
      )
      
      if response.success?
        results[name] = response.parsed_response['records']
      else
        puts "Error searching for person #{name}: #{response.code} - #{response.body}"
        results[name] = []
      end
    end
    
    results
  end
end 