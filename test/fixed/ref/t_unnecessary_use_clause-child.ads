package T_Unnecessary_Use_Clause.Child is
      -- Use clause from child
   Other_Pi : constant := My_Pi;

   use T_Unnecessary_Use_Clause.Parent_Pack;
   V : Integer := Data;
end T_Unnecessary_Use_Clause.Child;
