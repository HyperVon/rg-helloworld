# frozen_string_literal: true

require 'digest'
require_relative 'adjudicator/version'

module Adjudicator
  SERVICE_NAME = 'adjudicator'
  MIN_CONFIDENCE = 0.30
  HIGH_CONFIDENCE = 0.40
  GAP_RATIO_THRESHOLD = 0.1

  module AdjudicatorImpl
    class << self
      def adjudicate_symbol(observations, layout)
        position_obs = observations['positionObservations'] || []
        full_phrase = observations['fullPhrase'] || {}
        full_symbols = full_phrase['symbols'] || []
        layout_index = build_layout_index(layout)

        results = []
        position_obs.each do |po|
          position = po['position']
          layout_entry = layout_index[position]
          next unless layout_entry.nil? || layout_entry[:width].positive?

          crop_candidate = po['candidate'] || '?'
          crop_conf = po['confidence'] || 0.0

          full_candidate = find_full_phrase_symbol(full_symbols, layout_entry)
          full_conf = full_candidate ? (full_candidate['confidence'] || 0.0) : 0.0

          agreement = full_candidate && full_candidate['text'] == crop_candidate
          accepted = [full_conf, crop_conf].max.to_f

          if (agreement && (full_conf > MIN_CONFIDENCE || crop_conf > MIN_CONFIDENCE)) ||
             (crop_conf >= HIGH_CONFIDENCE)
            results << build_accepted(position, crop_candidate, crop_conf, full_candidate,
                                      crop_candidate, !agreement.nil?, layout_entry)
          else
            results << {
              position: position,
              tokenType: 'SYMBOL',
              utf8: crop_candidate,
              confidence: accepted,
              evidence: {
                fullPhraseCandidate: full_candidate ? full_candidate['text'] : nil,
                cropCandidate: crop_candidate,
                agreement: !agreement.nil?
              },
              qualityRetry: true
            }
          end
        end
        results
      end

      def adjudicate_gaps(observations, _layout)
        spacing_obs = observations.dig('observations', 'spacingObservations') ||
                      observations['spacingObservations'] || []
        return [] if spacing_obs.empty?

        ratios = spacing_obs.map { |s| (s['medianGlyphGapRatio'] || 0.0).to_f }
        median_ratio = calculate_median(ratios)
        threshold = [median_ratio * GAP_RATIO_THRESHOLD, GAP_RATIO_THRESHOLD].max

        results = []
        spacing_obs.each do |s|
          ratio_ok = s['medianGlyphGapRatio'] && s['medianGlyphGapRatio'] > threshold
          pixel_ok = s['pixelGap'] && s['pixelGap'].to_i > 100
          next unless ratio_ok || pixel_ok

          positions = s['betweenPositions']
          results << {
            position: positions ? positions[0] : nil,
            nextPosition: positions && positions[1],
            tokenType: 'GAP',
            utf8: ' ',
            confidence: [s['medianGlyphGapRatio'] / 5.0, 1.0].min,
            evidence: {
              agreement: true,
              medianGlyphGapRatio: s['medianGlyphGapRatio'],
              threshold: threshold
            }
          }
        end
        results
      end

      def check_prohibited_fields(event_json)
        violations = []
        prohibited = %w[targetText expectedCharacter unicodeCodePoint characterName glyphLabel]
        prohibited.each do |field|
          violations << field if event_json.include?("\"#{field}\"")
        end
        violations
      end

      def build_symbol_event(run_id, step_id, glyph_instance_id, attempt, position, symbol)
        operation_id = build_operation_id(run_id, step_id, attempt, [glyph_instance_id])
        {
          specversion: '1.0',
          id: operation_id,
          source: SERVICE_NAME,
          type: 'rg.symbols-adjudicated.v1',
          subject: "runs/#{run_id}",
          time: Time.now.utc.iso8601,
          correlationid: run_id,
          datacontenttype: 'application/json',
          data: {
            runId: run_id,
            stepId: step_id,
            glyphInstanceId: glyph_instance_id,
            position: position,
            attempt: attempt,
            inputMaturity: 70,
            outputMaturity: 80,
            inputArtifacts: [],
            outputArtifacts: [],
            transformation: { name: 'adjudicate-symbol', version: '1.0.0' },
            symbol: symbol
          }
        }
      end

      def build_quality_retry_event(run_id, step_id, attempt, position, reason)
        {
          specversion: '1.0',
          id: "retry-#{run_id}-#{position}-#{attempt}",
          source: SERVICE_NAME,
          type: 'rg.quality-retry.v1',
          subject: "runs/#{run_id}",
          time: Time.now.utc.iso8601,
          correlationid: run_id,
          datacontenttype: 'application/json',
          data: {
            runId: run_id,
            stepId: step_id,
            attempt: attempt,
            reason: reason,
            position: position,
            inputMaturity: 70,
            outputMaturity: 70
          }
        }
      end

      def adjudicate(observations, layout, run_id: 'test-run', step_id: 'test-step', attempt: 1)
        violations = check_prohibited_fields(observations.to_json)
        raise "Prohibited fields detected: #{violations.join(', ')}" unless violations.empty?

        symbols = adjudicate_symbol(observations, layout)
        gaps = adjudicate_gaps(observations, layout)

        retry_events = symbols.select { |s| s[:qualityRetry] }.map do |s|
          build_quality_retry_event(run_id, step_id, attempt, s[:position], 'ambiguous')
        end

        accepted_symbols = symbols.reject { |s| s[:qualityRetry] }

        {
          acceptedSymbols: accepted_symbols,
          gaps: gaps,
          retryEvents: retry_events,
          allAccepted: retry_events.empty?
        }
      end

      def run_once(input_path, layout_path, output_path: nil, event_output_path: nil)
        observations = JSON.parse(File.read(input_path))
        layout = JSON.parse(File.read(layout_path))['layout']

        result = adjudicate(observations, layout)

        File.write(output_path, JSON.pretty_generate(deep_stringify(result))) if output_path

        if event_output_path
          events = result[:acceptedSymbols].map.with_index do |sym, _idx|
            build_symbol_event(
              'test-run', 'test-step', 'glyph-1', 1, sym[:position], sym
            )
          end
          File.write(event_output_path, JSON.pretty_generate(events))
        end

        result
      end

      private

      def deep_stringify(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
        when Array
          obj.map { |v| deep_stringify(v) }
        else
          obj
        end
      end

      def find_full_phrase_symbol(full_symbols, layout_entry)
        position = layout_entry ? layout_entry[:position] : nil
        x = layout_entry ? layout_entry[:x] : nil
        full_symbols.find do |s|
          s['position'] == position || s['x'] == x
        end
      end

      def geometrically_aligned?(full_symbols, layout_entry, crop_candidate)
        symbol = find_full_phrase_symbol(full_symbols, layout_entry)
        return false unless symbol

        symbol['text'] == crop_candidate && symbol['confidence'].to_f > HIGH_CONFIDENCE
      end

      def build_accepted(position, utf8, confidence, full_symbol, crop_candidate, agreement,
                         _layout_entry)
        {
          position: position,
          tokenType: 'SYMBOL',
          utf8: utf8,
          confidence: confidence,
          evidence: {
            fullPhraseCandidate: full_symbol ? full_symbol['text'] : nil,
            cropCandidate: crop_candidate,
            agreement: agreement
          }
        }
      end

      def calculate_median(values)
        sorted = values.sort
        n = sorted.length
        return 0 if n.zero?
        return sorted[n / 2].to_f if n.odd?

        (sorted[(n / 2) - 1].to_f + sorted[n / 2].to_f) / 2.0
      end

      def build_layout_index(layout)
        index = {}
        layout.each do |entry|
          index[entry['position']] = {
            position: entry['position'],
            x: entry['x'] || 0,
            y: entry['y'] || 0,
            width: (entry['width'] || 0).to_i,
            height: (entry['height'] || 0).to_i
          }
        end
        index
      end

      def build_operation_id(run_id, step_id, attempt, input_hashes)
        payload = {
          runId: run_id,
          stepId: step_id,
          attempt: attempt,
          inputs: input_hashes.sort
        }.to_json
        Digest::SHA256.hexdigest(payload)
      end
    end
  end

  def self.banner
    "#{SERVICE_NAME} #{VERSION} (Milestone 8)"
  end
end
