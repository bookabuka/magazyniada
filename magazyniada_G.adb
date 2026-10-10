
with Ada.Text_IO;  use Ada.Text_IO;
with Ada.Calendar; use Ada.Calendar;
with Ada.Numerics.Float_Random;

procedure Magazyniada is

   Truck_Count : constant := 6;
   Tick        : constant Duration := 0.1;

   subtype Robot_Id is Positive range 1 .. 2;

   type Robot_States is array (Robot_Id) of Boolean; -- [G] Statusy robotow

   type Goods is (Koperty, Paczki, Palety);
   type Stock is array (Goods) of Natural;

   type Cargo is record
      Id    : Positive;
      Kind  : Goods;
      Count : Positive;
   end record;

   package FR renames Ada.Numerics.Float_Random;

   T0 : constant Time := Clock;

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Img (C : Cargo) return String is
     (Img (C.Count) & " szt. " & Goods'Image (C.Kind));

   function Img (S : Stock; K : Goods := Goods'First) return String is
      Part : constant String := Goods'Image (K) & "=" & Img (S (K));
   begin
      if K = Goods'Last then
         return Part;
      end if;
      return Part & " " & Img (S, Goods'Succ (K));
   end Img;

   function Stamp return String is
      T   : constant Natural := Natural ((Clock - T0) * 10);
      Sec : constant String  := Img (T / 10);
   begin
      return "[" & (if Sec'Length < 2 then "0" else "") &
             Sec & "." & Img (T mod 10) & "]";
   end Stamp;

   procedure Log (Msg : String) is
   begin
      Put (Stamp & " " & Msg & ASCII.LF);
   end Log;

   protected Dice is
      procedure Roll (Lo, Hi : Integer; N : out Integer);
   private
      Gen   : FR.Generator;
      Ready : Boolean := False;
   end Dice;

   protected body Dice is
      procedure Roll (Lo, Hi : Integer; N : out Integer) is
      begin
         if not Ready then
            FR.Reset (Gen);
            Ready := True;
         end if;

         N := Integer'Min
           (Hi, Lo + Integer
              (Float'Floor
                 (FR.Random (Gen) * Float (Hi - Lo + 1))));
      end Roll;
   end Dice;

   function Random_In (Lo, Hi : Integer) return Integer is
      N : Integer;
   begin
      Dice.Roll (Lo, Hi, N);
      return N;
   end Random_In;

   function Random_Goods return Goods is
     (Goods'Val (Random_In (0, Goods'Pos (Goods'Last))));

   procedure Pause (Lo, Hi : Positive) is
   begin
      delay Tick * Random_In (Lo, Hi);
   end Pause;

   task Dock is
      entry Arrive (D : Cargo);
   end Dock;

   task type Robot is
      entry Init  (N : Robot_Id);
      entry Carry (C : Cargo);
   end Robot;

   Robots : array (Robot_Id) of Robot;

   task Warehouse is
      entry Store (K : Goods; N : Positive);
      entry Status (S : out Stock);

      -- [G] Odczyt licznika i statusow robotow
      entry Get_Count (N : out Natural);
      entry Set_Robot_State (R : Robot_Id; Free : Boolean);
      entry Get_Robot_States (S : out Robot_States);
   end Warehouse;

   task type Truck (Id : Positive);
   task Arrivals;

   procedure Send_To_Robot (C : Cargo) is
   begin
      loop
         for R in Robot_Id loop
            select
               Robots (R).Carry (C);
               return;
            else
               null;
            end select;
         end loop;

         delay Tick;
      end loop;
   end Send_To_Robot;

   task body Dock is
      Load : Cargo;
   begin
      loop
         select
            accept Arrive (D : Cargo) do
               Log ("Rozpoczeto rozladunek D" & Img (D.Id));
               Pause (20, 40);
               Log ("Zakonczono rozladunek D" & Img (D.Id));
               Load := D;
            end Arrive;

            Send_To_Robot (Load);

         or
            terminate;
         end select;
      end loop;
   end Dock;

   task body Robot is
      Id  : Robot_Id;
      Job : Cargo;
      S   : Stock;

      procedure Say (Msg : String) is
      begin
         Log ("Robot R" & Img (Id) & " " & Msg);
      end Say;

   begin
      accept Init (N : Robot_Id) do
         Id := N;
      end Init;

      loop
         select
            accept Carry (C : Cargo) do
               Job := C;
               Say ("otrzymal " & Img (C));
            end Carry;

            Warehouse.Set_Robot_State (Id, False); -- [G] Zajety

         or
            terminate;
         end select;

         Say ("jedzie do magazynu");
         Pause (30, 60);

         Warehouse.Store (Job.Kind, Job.Count);
         Warehouse.Status (S);

         Say ("dostarczyl towar (magazyn: " & Img (S) & ")");

         Warehouse.Set_Robot_State (Id, True); -- [G] Wolny
         Say ("jest ponownie wolny");
      end loop;
   end Robot;

   task body Warehouse is
      Items : Stock := (others => 0);
      Delivered_Count : Natural := 0; -- [G] Licznik dostaw
      States : Robot_States := (others => True); -- [G] Statusy robotow

   begin
      loop
         select
            accept Store (K : Goods; N : Positive) do
               Items (K) := Items (K) + N;
               Delivered_Count := Delivered_Count + 1; -- [G] Nowa dostawa
            end Store;

         or
            accept Status (S : out Stock) do
               S := Items;
            end Status;

         or
            accept Get_Count (N : out Natural) do
               N := Delivered_Count;
            end Get_Count;

         or
            accept Set_Robot_State
              (R : Robot_Id; Free : Boolean) do
               States (R) := Free;
            end Set_Robot_State;

         or
            accept Get_Robot_States (S : out Robot_States) do
               S := States;
            end Get_Robot_States;

         or
            terminate;
         end select;
      end loop;
   end Warehouse;

   -- [G] Monitor centrum logistycznego

   task Monitor;

   task body Monitor is
      S        : Stock;
      Count    : Natural := 0;
      Statuses : Robot_States;

   begin
      Put_Line ("stan magazynu:");

      loop
         -- Pobranie aktualnych danych
         Warehouse.Status (S);
         Warehouse.Get_Count (Count);
         Warehouse.Get_Robot_States (Statuses);

         Put_Line(" ");
         Put_Line("=====MONITOR=====");
         Log ("stan magazynu: " & Img (S));
         Log ("dostarczone ladunki: " & Img (Count));

         -- Status obu robotow
         for R in Robot_Id loop
            Log ("Robot R" & Img (R) & ": " &
                 (if Statuses (R) then "Wolny" else "Zajety"));
         end loop;
         Put_Line("=================");
         Put_Line(" ");

         exit when Count = Truck_Count; -- [G] Do zmiany przy module H
         delay 3.0;
      end loop;

   end Monitor;

   task body Truck is
      D : constant Cargo :=
        (Id, Random_Goods, Random_In (1, 10));

   begin
      Log ("Przyjazd samochodu D" & Img (Id) &
           ": " & Img (D));

      Log ("D" & Img (Id) & " oczekuje na rozladunek");

      Dock.Arrive (D);
   end Truck;

   task body Arrivals is
      type Truck_Ref is access Truck;
      Ref : Truck_Ref;

   begin
      for I in 1 .. Truck_Count loop
         Pause (5, 40);
         Ref := new Truck (I);
      end loop;
   end Arrivals;

begin
   Log ("Start symulacji");

   for R in Robot_Id loop
      Robots (R).Init (R);
   end loop;

end Magazyniada;
