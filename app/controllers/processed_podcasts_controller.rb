class ProcessedPodcastsController < ApplicationController
  def index
    @processed_podcasts = ProcessedPodcast.all
    # Group by date for display (optional, could also sort)
    @grouped_podcasts = @processed_podcasts.group_by { |p| p.processed_at&.to_date }
                                            .sort_by { |date, _| date || Date.new(1970) } # Handle nil dates
                                            .reverse
                                            .to_h
  end

  def show
    # Filename comes URL-encoded from the route
    encoded_filename = params[:filename]
    begin
      # Decode the filename
      decoded_filename = URI.decode_www_form_component(encoded_filename)
      @podcast = ProcessedPodcast.find_by_summary_filename(decoded_filename)

      if @podcast.nil?
        Rails.logger.warn("ProcessedPodcast not found for filename: #{decoded_filename} (encoded: #{encoded_filename})")
        # Optionally, redirect to index or show a not found page
        flash[:alert] = "Podcast summary not found for the given filename."
        redirect_to processed_podcasts_path
        return
      end
      # Summary content will be loaded via @podcast.summary_content in the view
    rescue ArgumentError => e
      Rails.logger.error("Error decoding filename: #{encoded_filename}. Error: #{e.message}")
      flash[:alert] = "Invalid filename format."
      redirect_to processed_podcasts_path
    rescue => e
      Rails.logger.error("Unexpected error in show action for filename: #{encoded_filename}. Error: #{e.message}")
      flash[:alert] = "An unexpected error occurred."
      redirect_to processed_podcasts_path
    end
  end
end 