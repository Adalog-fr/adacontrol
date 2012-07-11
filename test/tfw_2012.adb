pragma Ada_2012;
procedure Tfw_2012 is
   -- Only for stress test.
   -- Does not test anything by itself (hence considered tfw),
   -- but contains a little digest of the most error-prone functionalities
   -- of Ada 2012, to make sure new rules are not trapped by them.

   subtype Sub is Integer range 1..10;

   I : Integer;
   J : Integer := (if I = 0 then 1 else 2);                        -- if expression

-- K : Integer := (case I = J is when False => 1, when True => 2); -- case expression

   function Is_Nul return Boolean is (I=0);                        -- expression function

   procedure P (I : in out Integer; J : out Integer)
     with Pre  => I /= 0,                                          -- Pre-condition
          Post => J = I'Old + 1 ;                                  -- Post-condition
   procedure P (I : in out Integer; J : out Integer) is
   begin
      J := I + 1;
   end P;

   B1 : Boolean := (for all  II in 1..10 => I mod J = 0);          -- Quantified expression
   B2 : Boolean := (for Some II in 1..10 => I mod J = 0);          -- Quantified expression

   type Even is range 1 .. 10
       with Dynamic_Predicate => Even mod 2 = 0;                   -- subtype predicates

                                                                   -- type invariant TBSL
   S : String (1..10);
begin
   for C of S loop                                                 -- for .. of
      C := ' ';
   end  loop;

   if I in 1 | 2 | Sub | 1..10 then                                -- multiple membership test
      null;
   end if;
end Tfw_2012;
