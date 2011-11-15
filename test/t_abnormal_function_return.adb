pragma Ada_2005;
with Ada.Exceptions; use Ada.Exceptions;
with Text_IO; use Text_IO;
function T_Abnormal_Function_Return return Integer is
   function F1 return Integer is
   begin
      return 0;
      null;                                         -- Sequence of statements
   exception
      when Tasking_Error =>
        Put_Line ("tasking_error");                 -- Sequence of statements
      when Constraint_Error =>
         begin
            return 1;
         exception
            when Constraint_Error =>
               begin
                  null;                            -- Sequence of statements
               end;
         end;
      when others =>
         null;                                      -- Sequence of statements
   end F1;

   function F2 (I : Integer) return Integer is
   begin
      if True then
         return 1;
      else
         return 2;
      end if;
   exception
      when Constraint_Error =>
         case I is
            when 1 =>
               if True then                          -- "else" path
                  return 0;
               elsif True then
                  null;                              -- Sequence of statements
               end if;
            when 2 =>
               if True then
                  return 0;
               elsif True then
                  return 1;
               else
                  return 2;
               end if;
            when 3 =>
               begin
                  raise;
               end;
            when 4 =>
               null;                                 -- Sequence of statements
            when 5 =>
               return I : Integer do
                  I := 0;
               end return;
            when 6 =>
               <<Hell>>                              -- exitable extended return
               return I : Integer do
                  I := 0;
                  goto Hell;
               end return;
            when others =>
               raise Program_Error;
         end case;
   end F2;

begin
   begin
      begin
         begin
            return 1;
         exception
            when Constraint_Error =>
               return 2;
         end;
      end;
   end;
exception
   when Constraint_Error =>
      Raise_Exception (Constraint_Error'Identity);
   when Program_Error =>
      null;
      raise;
   when Storage_Error =>
      null;
      raise Storage_Error;
   when Occur : Tasking_Error =>
      Reraise_Occurrence (Occur);
   when others =>
      return 0;
end T_Abnormal_Function_Return;
