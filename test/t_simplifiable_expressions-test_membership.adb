separate (t_simplifiable_expressions)
procedure Test_Membership is
   I1, I2 : Integer;
   I3     : Integer renames I1;

   Cond : Boolean;
begin
   Cond := ((I1) = 1) or (I1 = 5 or I1 = 10) or I3 = 0 or Test_Membership.I1 = 9;          -- Replaceable by in
   Cond := I1 = 1 or I1 in 12 .. 15;                                                       -- Replaceable by in
   Cond := I1 = 1 or (I2 = 2 or I2 = 3);                                                   -- Replaceable by in (subexpression)
   Cond := I1 = 1 or (I1 = 2 or I2 = 3);
   Cond := I1 = 1 or  I1 = 2 or I2 = 3;                                                    -- Replaceable by in
   Cond := I1 = 1 and (I1 = 5 or I1 = 10);                                                 -- Replaceable by in (subexpression)
   Cond := I1 in 1 .. 2 or (I1 >= 3 and I1 <= 5);                                          -- Replaceable by in
   Cond := I1 in 1 .. 2 or (I1 <= 5 and I1 >= 3);                                          -- Replaceable by in
   Cond := I1 in 1 .. 2 or (I1 < 5 and I2 >= 3);
   Cond := I1 in 1 .. 2 or (I1 > 3 or  I1 <= 5);

   Cond := ((I1) /= 1) and (I1 /= 5 and I1 /= 10) and I3 /= 0 and Test_Membership.I1 /= 9; -- Replaceable by not in
   Cond := I1 /= 1 and I1 not in 12 .. 15;                                                 -- Replaceable by not in
   Cond := I1 /= 1 and (I2 /= 2 and I2 /= 3);                                              -- Replaceable by not in (subexpression)
   Cond := I1 /= 1 or (I1 /= 5 and I1 /= 10);                                              -- Replaceable by not in (subexpression)

   -- Check complex variables (Eurocontrol bug report)
   declare
      type Rchar is
         record
            C : Character;
         end record;
      type Arr1 is array (1 .. 3) of Rchar;
      type Arr2 is array (1 .. 3) of Arr1;
      type Rec is
         record
            Comp1 : Arr1;
            Comp2 : Arr2;
         end record;
      V : Rec;
   begin
      if V.Comp1 (1).C = ' '  or V.Comp1 (1).C = 'a' then                                  -- Replaceable by in
         null;
      end if;

      if V.Comp2 (1) (1).C = ' '  or V.Comp2 (1) (1).C = 'a' then                          -- Replaceable by in
         null;
      end if;
   end;
end Test_Membership;
