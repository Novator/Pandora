module Pandora
  module Utils

    # Round queue buffer
    # RU: Циклический буфер
    class RoundQueue < Mutex
      # Init empty queue. Poly read is possible
      # RU: Создание пустой очереди. Возможно множественное чтение
      attr_accessor :queue, :write_ind, :read_ind

      def initialize(poly_read=false)   #init_empty_queue
        super()
        @queue = Array.new
        @write_ind = -1
        if poly_read
          @read_ind = Array.new  # will be array of read pointers
        else
          @read_ind = -1
        end
      end

      MaxQueue = 20

      # Add block to queue
      # RU: Добавить блок в очередь
      def add_block_to_queue(block, max=MaxQueue)
        res = false
        if block
          synchronize do
            if write_ind<max
              @write_ind += 1
            else
              @write_ind = 0
            end
            queue[write_ind] = block
          end
          res = true
        end
        res
      end

      QS_Empty     = 0
      QS_NotEmpty  = 1
      QS_Full      = 2

      # State of single queue
      # RU: Состояние одиночной очереди
      def single_read_state(max=MaxQueue)
        res = QS_NotEmpty
        if @read_ind.is_a? Integer
          if (@read_ind == write_ind)
            res = QS_Empty
          else
            wind = write_ind
            if wind<max
              wind += 1
            else
              wind = 0
            end
            res = QS_Full if (@read_ind == wind)
          end
        end
        res
      end

      # Get block from queue (set "reader" like 0,1,2..)
      # RU: Взять блок из очереди (задавай "reader" как 0,1,2..)
      def get_block_from_queue(max=MaxQueue, reader=nil)
        block = nil
        pointers = nil
        synchronize do
          ind = @read_ind
          if reader
            pointers = ind
            ind = pointers[reader]
            ind ||= -1
          end
          #p 'get_block_from_queue:  [reader, ind, write_ind]='+[reader, ind, write_ind].inspect
          if ind != write_ind
            if ind<max
              ind += 1
            else
              ind = 0
            end
            block = queue[ind]
            if reader
              pointers[reader] = ind
            else
              @read_ind = ind
            end
          end
        end
        block
      end
    end

  end
end