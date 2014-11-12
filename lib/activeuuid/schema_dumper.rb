require 'active_record/schema_dumper'

class ActiveRecord::SchemaDumper
  private

  def table(table, stream)
    columns = @connection.columns(table)
    begin
      tbl = StringIO.new

      pk_is_activeuuid = false

      # first dump primary key column
      if @connection.respond_to?(:pk_and_sequence_for)
        pk, _ = @connection.pk_and_sequence_for(table)
      end
      if !pk && @connection.respond_to?(:primary_key)
        pk = @connection.primary_key(table)
      end

      tbl.print "  create_table #{remove_prefix_and_suffix(table).inspect}"
      pkcol = columns.detect { |c| c.name == pk }
      if pkcol
        if pkcol.sql_type == 'binary(16)'
          tbl.print ", id: false"
          pk_is_activeuuid = true
        elsif pk != 'id'
          tbl.print %Q(, primary_key: "#{pk}")
        elsif pkcol.sql_type == 'uuid'
          tbl.print ", id: :uuid"
          tbl.print %Q(, default: "#{pkcol.default_function}") if pkcol.default_function
        end
      else
        tbl.print ", id: false"
      end
      tbl.print ", force: true"
      tbl.puts " do |t|"

      # then dump all non-primary key columns
      column_specs = columns.map do |column|
        raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" unless @connection.valid_type?(column.type)
        next if !pk_is_activeuuid and column.name == pk
        @connection.column_spec(column, @types)
      end.compact

      # find all migration keys used in this table
      keys = @connection.migration_keys

      # figure out the lengths for each column based on above keys
      lengths = keys.map { |key|
        column_specs.map { |spec|
          spec[key] ? spec[key].length + 2 : 0
        }.max
      }

      # the string we're going to sprintf our values against, with standardized column widths
      format_string = lengths.map{ |len| "%-#{len}s" }

      # find the max length for the 'type' column, which is special
      type_length = column_specs.map{ |column| column[:type].length }.max

      # add column type definition to our format string
      format_string.unshift "    t.%-#{type_length}s "

      format_string *= ''

      column_specs.each do |colspec|
        values = keys.zip(lengths).map{ |key, len| colspec.key?(key) ? colspec[key] + ", " : " " * len }
        values.unshift colspec[:type]
        tbl.print((format_string % values).gsub(/,\s*$/, ''))
        tbl.puts
      end

      tbl.puts "  end"
      tbl.puts

      indexes(table, tbl)

      tbl.rewind
      stream.print tbl.read
    rescue => e
      stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
      stream.puts "#   #{e.message}"
      stream.puts
    end

    stream
  end
end
